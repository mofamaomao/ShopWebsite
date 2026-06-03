# Phase 8 — M1: RabbitMQ 异步下单

## 目标

将同步下单（SELECT FOR UPDATE + 直接写 DB）改造为异步架构：
Redis Lua 原子预扣库存 → MQ 发布确认 → Consumer 幂等写 DB。

## 架构决策

| 关注点 | 方案 |
|---|---|
| 库存扣减并发安全 | Redis Lua 脚本原子预扣（`order_deduct.lua`），替代 Redisson 分布式锁 |
| 消息可靠性 | Spring AMQP Publisher Confirm (`correlated`)，等待 Broker ack（≤3s）|
| 消费端幂等 | `order_no VARCHAR(36) UNIQUE`，`DuplicateKeyException` 视为成功 |
| 消费失败兜底 | Manual ACK + basicNack(requeue=false) → DLX/DLQ |
| 接口响应 | 立即返回 `{orderId, status:"PROCESSING"}`，DB 写入异步完成 |

## 新增 / 修改文件

### 新增

| 文件 | 说明 |
|---|---|
| `config/RabbitMQConfig.java` | Exchange/Queue/DLQ Bean、JSON MessageConverter、ListenerContainerFactory |
| `mq/OrderMessage.java` | 消息体（orderId, userId, items+价格快照, createTime） |
| `mq/OrderProducer.java` | send() 阻塞等待 confirm，超时/nack 返回 false |
| `mq/OrderConsumer.java` | @RabbitListener + manual ACK，失败转 DLQ |
| `service/OrderPersistService.java` | 接口 |
| `service/impl/OrderPersistServiceImpl.java` | 幂等 persist：先减库存再插 Order+OrderItem |
| `lua/order_deduct.lua` | 返回 1(成功)/0(库存不足)/-1(key 不存在) |
| `docs/migration_mq.sql` | `ALTER TABLE order ADD COLUMN order_no VARCHAR(36) UNIQUE` |

### 修改

| 文件 | 变更 |
|---|---|
| `pom.xml` | 新增 `spring-boot-starter-amqp` |
| `application.yml` | RabbitMQ 连接 + publisher-confirm-type + manual ack + retry |
| `entity/Order.java` | 新增 `orderNo` 字段 |
| `vo/OrderVO.java` | `orderId` 类型 Long → String |
| `common/RedisKeyConstants.java` | 新增 `ORDER_STOCK_PREFIX` + `orderStockKey()` |
| `common/Result.java` | 新增 `ok(String msg, T data)` 重载 |
| `config/SeckillConfig.java` | 新增 `orderDeductScript` Bean |
| `mapper/OrderMapper.java` | 新增 `existsByOrderNo()` |
| `resources/mapper/OrderMapper.xml` | resultMap + INSERT 加 order_no |
| `service/impl/OrderServiceImpl.java` | 重写为异步流程（无 Redisson，无直接 DB 写） |
| `controller/OrderController.java` | 返回 `Result.ok("订单处理中", vo)` |

## 关键实现细节

### Redis Lua 预扣（懒加载）

```java
// key 不存在时从 DB 初始化，setIfAbsent 防并发重复初始化
stringRedisTemplate.opsForValue()
    .setIfAbsent(key, String.valueOf(product.getStock()), 2, TimeUnit.HOURS);

// Lua 原子扣减，失败立即回滚已扣数量
Long result = stringRedisTemplate.execute(orderDeductScript,
    Collections.singletonList(key), String.valueOf(quantity));
```

### Publisher Confirm 等待

```java
CorrelationData cd = new CorrelationData(message.getOrderId());
rabbitTemplate.convertAndSend(ORDER_EXCHANGE, ORDER_KEY, message, cd);
CorrelationData.Confirm confirm = cd.getFuture().get(3, TimeUnit.SECONDS);
return confirm.isAck();
```

### Consumer 幂等写 DB

```java
if (orderMapper.existsByOrderNo(message.getOrderId())) return; // 已处理
// decreaseStock → insert Order → insert OrderItem
// catch DuplicateKeyException → return（并发竞争兜底）
```

## 编译错误 & 修复

| 错误 | 原因 | 修复 |
|---|---|---|
| `SimpleRabbitListenerContainerFactoryConfigurer` not found | Spring Boot 3 中该类在 `org.springframework.boot.autoconfigure.amqp` 包，不在 `amqp.rabbit.listener` | 修正 import 路径 |
| `RabbitMQConfig` symbol not found in `OrderProducer/OrderConsumer` | `mq` 包中未 import `config.RabbitMQConfig` | 添加 import |

## 接口响应示例

```json
POST /api/orders
{
  "code": 200,
  "msg": "订单处理中",
  "data": {
    "orderId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "PROCESSING"
  }
}
```

## 测试结果

### Lua 脚本单元测试（redis-cli --eval，Docker shop-redis）

| 用例 | 命令 | 预期 | 实际 |
|---|---|---|---|
| 正常扣减 | stock=5，deduct=2 | 1 | ✅ 1 |
| 连续扣减 | stock=3，deduct=2 | 1 | ✅ 1 |
| 库存不足 | stock=1，deduct=5 | 0 | ✅ 0 |
| key 不存在 | stock:999，deduct=1 | -1 | ✅ -1 |

> **Windows PowerShell 注意**：`redis-cli --eval script.lua key , arg` 中的逗号需加引号 `","` 否则 PowerShell 将其解析为数组运算符，导致 ARGV 为空。

### API 集成测试

| 用例 | 请求 | 预期响应 | 实际 |
|---|---|---|---|
| 正常下单 | POST /api/orders qty=1 | 200 订单处理中 + UUID orderId | ✅ orderId=afd1d8ac-f7fc-4af2-9af4-cc5024e345d8 |
| Consumer 写 DB | 查 order 表 order_no | status=PAID，total_price=9999.00 | ✅ id=47 |
| 库存不足拦截 | order:stock:1=0，qty=1 | 1003 库存不足 | ✅ code=1003 |

### 实际接口响应

```json
{
  "code": 200,
  "msg": "订单处理中",
  "data": {
    "orderId": "afd1d8ac-f7fc-4af2-9af4-cc5024e345d8",
    "status": "PROCESSING"
  }
}
```

### 调试过程记录

| 问题 | 原因 | 解决 |
|---|---|---|
| `migration_mq.sql` 导入报错 1064 | `ADD COLUMN IF NOT EXISTS` 是 MySQL 8.0.3+ 语法 | 去掉 `IF NOT EXISTS`，改 `NOT NULL DEFAULT ''` 为 `NULL` |
| Lua EVAL 返回 nil 错误 | PowerShell `,` 是数组运算符，逗号未传给 redis-cli | 改为 `"," ` 加引号 |
| Lua 始终返回 0 | 应用运行时 `DECRBY` 已把 Redis stock 扣至 0 | 停应用后单独测 Lua 脚本 |
| 登录 400 | 接口字段是 `phone` 非 `username` | 改用 `{"phone":"...","password":"..."}` |
| MySQL 查询 `\o` 错误 | PowerShell 反引号是转义符，`` \`o `` 变成 `\o` | 用双反引号 ` `` ` 表示字面反引号 |
