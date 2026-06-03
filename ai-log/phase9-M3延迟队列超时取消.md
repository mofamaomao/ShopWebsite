# Phase 9 — M3：延迟队列 + 订单超时取消

## 目标

在 M1/M2 异步下单 + 可靠投递基础上，增加订单 30 分钟未支付自动取消并恢复库存：
- 方案 A（TTL+DLX，无需插件）：delay.queue TTL 到期 → cancel.queue → 取消消费者
- 取消：更新状态 CANCELLED + 恢复 MySQL 库存 + 恢复 Redis 库存
- 幂等：仅处理 PENDING_PAYMENT 状态，其他状态直接 ACK 跳过
- 消费失败 basicNack(requeue=false)，不循环重试

## 架构

```
OrderPersistServiceImpl
  └── persist() 成功后 → convertAndSend(ORDER_DELAY_EXCHANGE, ORDER_DELAY_KEY, cancelMsg)
                                  ↓ TTL=${order.timeout-ms} (测试:60s)
                         order.delay.queue  ──── x-message-ttl ────→ DLX: order.cancel.exchange
                                                                           ↓ routing-key: order.cancel.queue
                                                                     order.cancel.queue
                                                                           ↓
                                                                   OrderCancelConsumer
                                                                     ├── status=PENDING_PAYMENT → cancelOrder()
                                                                     └── 其他状态 → ACK skip

OrderServiceImpl.cancelOrder(orderNo)  [@Transactional]
  ├── findByOrderNo → 找不到/非PENDING_PAYMENT → return (幂等)
  ├── orderMapper.update(CANCELLED)
  ├── productMapper.increaseStock (MySQL 恢复)
  └── redisTemplate.increment    (Redis 恢复)
```

## 新增 / 修改文件

### 新增
| 文件 | 说明 |
|---|---|
| `mq/OrderCancelMessage.java` | 延迟取消消息（orderId, userId, orderCreateTime）|
| `mq/OrderCancelConsumer.java` | 监听 order.cancel.queue，调用 cancelOrder |
| `docs/design/mq-order-adr.md` | 中文 ADR，含架构对比 + 方案选型 + 可靠性链路 |

### 修改
| 文件 | 变更 |
|---|---|
| `config/RabbitMQConfig.java` | 新增 ORDER_DELAY_EXCHANGE/KEY + delay/cancel 队列声明 + @Value TTL |
| `mapper/OrderMapper.java` | 新增 findByOrderNo(String orderNo) |
| `mapper/ProductMapper.java` | 新增 increaseStock |
| `resources/mapper/OrderMapper.xml` | findByOrderNo SQL |
| `resources/mapper/ProductMapper.xml` | increaseStock SQL |
| `service/OrderService.java` | 新增 cancelOrder(String orderNo) |
| `service/impl/OrderServiceImpl.java` | 实现 cancelOrder + 注入 OrderMapper/OrderItemMapper |
| `service/impl/OrderPersistServiceImpl.java` | 注入 RabbitTemplate，写库后发延迟消息，status 改 PENDING_PAYMENT |
| `resources/application.yml` | 新增 order.timeout-ms: 60000 |

## 测试方案

### Test 1 — 超时自动取消（核心验证）
```powershell
# 前置：重置库存，启动应用 (order.timeout-ms=60000)
# 1. 下单
$token = Get-Token
$oid = Place-Order $token
Write-Info "orderId=$oid"

# 2. 确认初始状态为 PENDING_PAYMENT
Start-Sleep 2
$status = mysql -u root -predhat shop_demo -N -e "SELECT status FROM ``order`` WHERE order_no='$oid';"
# Expected: PENDING_PAYMENT

# 3. 等待 TTL (65s) 后检查
Start-Sleep 65
$status2 = mysql -u root -predhat shop_demo -N -e "SELECT status FROM ``order`` WHERE order_no='$oid';"
# Expected: CANCELLED

# 4. 检查库存恢复
$stock = mysql -u root -predhat shop_demo -N -e "SELECT stock FROM product WHERE id=1;"
$redisStock = docker exec shop-redis redis-cli GET order:stock:1
# Expected: 两者均已恢复（+1）
```

### Test 2 — 幂等：已支付订单不被取消
```powershell
# 下单后手动将状态更新为 PAID
$oid = Place-Order $token
Start-Sleep 2
mysql -u root -predhat shop_demo -e "UPDATE ``order`` SET status='PAID' WHERE order_no='$oid';"
# 等待 TTL 到期后检查，订单状态仍为 PAID（不被取消）
Start-Sleep 65
$status = mysql ... # Expected: PAID（未变）
```

### Test 3 — RabbitMQ 管理面板验证
```
访问 http://localhost:15672
登录后检查 Queues 列表：
  order.delay.queue  ── TTL=60000ms, DLX=order.cancel.exchange
  order.cancel.queue ── 正常消费
下单后可看到 order.delay.queue 中有 1 条 Ready 消息，60s 后消失并触发 cancel
```

### Test 4 — ADR 字数验证
```
wc -w docs/design/mq-order-adr.md
# Expected: ≥400
```

## 验收清单

| 验收项 | 状态 |
|---|---|
| 下单 60s 后订单变 CANCELLED | 需运行时验证 |
| MySQL 库存恢复（+qty） | 需运行时验证 |
| Redis 库存恢复（+qty） | 需运行时验证 |
| PAID 订单不被取消（幂等） | 需运行时验证 |
| order.delay.queue 可见 TTL=60000 | 需运行时验证 |
| order.cancel.queue 可见 | 需运行时验证 |
| docs/design/mq-order-adr.md 字数≥400 | ✅（实际约700字） |
| @Value TTL 注入，无硬编码 | ✅ |
| basicNack(requeue=false) | ✅ |
| 编译通过 | ✅ |

## 推送状态

本地提交：
- `448ba5e` feat(M3): delayed queue + order timeout cancellation (TTL+DLX)
- `338c204` fix(M3): align with task spec

**GitHub 推送失败（403）**：此 CCR 会话的 GitHub App 集成仅有读权限，写权限未授权。
解决方案：在 GitHub 仓库 Settings → Integrations 中授权 Claude Code App 写权限，或执行：
```bash
git push https://<username>:<PAT>@github.com/mofamaomao/ShopWebsite.git claude/jolly-edison-MpzBv
```

## 关键设计说明

- `order.delay.queue` 使用 `x-message-ttl`（队列级别 TTL），所有消息共享同一超时窗口
- 方案 B（rabbitmq-delayed-message-exchange 插件）支持消息级别 TTL，适合生产环境差异化超时，本 Demo 因 Docker 镜像限制未采用
- `cancelOrder` 加 `@Transactional`：更新状态 + 恢复 MySQL 库存在同一事务，Redis 恢复在事务提交后执行（Redis 不参与 DB 事务）
- Consumer `basicNack(requeue=false)`：取消失败不重试，防止 order.cancel.queue 堆积死循环
