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

## 测试要点

1. 正常下单：Redis 有库存 → ack → 返回 orderId
2. 库存不足：Lua 返回 0 → 400 STOCK_INSUFFICIENT
3. MQ nack（Broker 重启）：回滚 Redis 库存 → 500
4. 重复消费：`existsByOrderNo` 命中 → 直接 ack，DB 不重复写
5. Consumer 异常：basicNack requeue=false → 消息进 DLQ
