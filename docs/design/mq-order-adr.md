# ADR：基于 RabbitMQ 的异步下单 + 可靠投递 + 订单超时取消

**状态：** 已采纳  
**日期：** 2026-06-03

---

## 背景

早期的同步下单实现存在三个明显缺陷：

1. **响应延迟高**：每次下单需要在一个 HTTP 请求内完成 Redis 扣库存、MySQL 写订单、写订单明细三步操作，P99 响应时间随并发量线性上升，高峰时可达数百毫秒。
2. **强耦合**：下单接口直接依赖 MySQL 可用性。任何一个从库延迟、连接池耗尽都会直接影响下单接口的可用性，故障半径大。
3. **突发流量无法削峰**：秒杀、限时活动场景下，瞬间并发写入 MySQL 会造成行锁竞争，数据库压力远超正常水位。

此外，不设订单超时机制会导致库存被永久占用：Redis 已扣减的库存无法释放，MySQL 写入的 `PENDING_PAYMENT` 记录长期堆积，影响真实可用库存数字。

---

## 决策

引入 RabbitMQ 将下单流程改为三段式异步架构：

1. **HTTP 接口层**：仅执行 Redis Lua 原子扣库存（≤5ms），生成订单 UUID，写 `mq_message` 表（status=0），发送 MQ 消息，立即返回 `PROCESSING` 状态。
2. **Consumer 层**：异步从队列消费消息，执行 MySQL 写订单、写订单明细、扣减 MySQL 库存，保证最终一致性。
3. **超时取消层**：下单成功后向延迟队列发送取消消息，TTL 到期后自动执行取消并释放 MySQL + Redis 库存。

---

## 架构对比

| 维度       | 同步下单                    | 异步 MQ 下单               |
|-----------|----------------------------|-----------------------------|
| 接口响应   | 等待 DB 写入（慢，>100ms）  | 立即返回（≤50ms）            |
| 耦合度     | HTTP 线程强依赖 MySQL       | Producer / Consumer 完全解耦 |
| 削峰       | 不支持，瞬时流量打穿 DB      | MQ 充当缓冲层，Consumer 匀速消费 |
| 幂等       | 依赖 HTTP 重试幂等性         | `order_no` 唯一键 + 消费端检查双重保障 |
| 库存一致性 | Redis + MySQL 在同一事务    | Redis 先扣 → MySQL 在 Consumer 侧扣，最终一致 |
| 复杂度     | 低，单一路径                | 需维护 MQ、幂等逻辑、消息状态表 |

---

## 延迟队列方案选型

### 方案 A：TTL + 死信交换机（本项目采用）

在 `order.delay.queue` 上设置 `x-message-ttl`（通过 `@Value("${order.timeout-ms:1800000}")` 注入，测试值 60000ms），消息过期后由 RabbitMQ 自动路由到 `order.cancel.exchange` → `order.cancel.queue`，Cancel Consumer 执行取消逻辑。

**优点：**
- 无需安装任何插件，官方 Docker 镜像开箱即用
- 配置简单，队列 TTL 参数一目了然
- 与现有 DLX（死信队列）机制共用概念，不引入新技术点

**局限：**
- 所有消息共享同一 TTL，无法为单条消息设置不同延迟时间
- 若队列头部有长时间未消费的消息，后续消息的 TTL 不会提前触发

### 方案 B：rabbitmq-delayed-message-exchange 插件（未采用）

通过 `x-delay` 消息头为每条消息指定独立延迟时间，适合不同品类商品设置差异化支付窗口（如预售商品 72 小时 vs 普通商品 30 分钟）的生产场景。

**不采用原因：** 需要进入 RabbitMQ 容器手动安装插件，`rabbitmq:3-management` 官方镜像不内置，无法通过 `docker-compose up` 一键拉起。Demo 场景 TTL 统一，方案 A 完全满足需求。在托管云环境（如阿里云 AMQP、AWS AmazonMQ）中若插件已内置，可优先选用方案 B。

---

## 消息可靠性保证

本项目通过四层机制确保消息从生产到消费的端到端可靠性：

1. **DB-First 写入**：`OrderServiceImpl` 在调用 `rabbitTemplate.convertAndSend` 之前，先向 `mq_message` 表写入一条 status=0（pending）记录。若 MQ 发送前宕机，重启后定时任务可扫描重投。

2. **Publisher Confirm**：`RabbitTemplate` 配置 `ConfirmCallback`，broker ACK 时将 `mq_message` 更新为 status=1（delivered），NACK 时更新为 status=2（failed）并触发定时重投流程。`ReturnsCallback` 捕获路由失败告警。

3. **定时重投**：`OrderRetryScheduler` 每 60 秒扫描 status=2 且 retry_count<3 的记录并重新发送；超过 3 次后消息进入 `order.dlq`，`OrderDlqConsumer` 标记 status=3（dead）并记录 ERROR 告警，人工介入。

4. **Consumer 幂等消费**：`OrderConsumer` 在持久化前通过 `order_no` 唯一约束检查是否已处理，重复消息直接 ACK 跳过。消费失败时使用 `ConcurrentHashMap` 记录重试次数，达 3 次后 `basicNack(requeue=false)` 路由到 `order.dlq`，防止无限循环。

---

## 订单状态流转

```
PROCESSING（HTTP 返回）
    ↓ Consumer 成功写库
PENDING_PAYMENT
    ↓ 用户支付（本 Demo 范围外）
PAID
    ↓ TTL 到期且仍为 PENDING_PAYMENT
CANCELLED（库存同步恢复）
```

取消逻辑在 `OrderServiceImpl.cancelOrder()` 中以 `@Transactional` 保证原子性：更新订单状态 → `productMapper.increaseStock()` 恢复 MySQL 库存 → `stringRedisTemplate.increment()` 恢复 Redis 计数，两者在同一事务 + 同一方法调用中执行，保证一致性。
