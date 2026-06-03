# Phase 9 — M3: Delayed Queue + Order Timeout Cancellation

## Objective

Implement order timeout auto-cancellation using TTL + Dead Letter Exchange (Method A):
- `order.delay.queue` (TTL via `@Value`) → expires → DLX routes to `order.cancel.queue`
- `OrderCancelConsumer`: idempotent check (PENDING_PAYMENT only) → `cancelOrder()`
- `cancelOrder()`: CANCELLED + restore MySQL stock + restore Redis stock (atomic `@Transactional`)
- `basicNack(requeue=false)` on failure — no retry loop
- ADR at `docs/design/mq-order-adr.md` (513 tokens)

## Architecture

```
OrderPersistServiceImpl.persist()
  ├── orderMapper.insert()          status = PENDING_PAYMENT
  └── rabbitTemplate.convertAndSend("", ORDER_DELAY_QUEUE, cancelMsg)
            │
            │ TTL=${order.timeout-ms} expires
            ▼
    order.cancel.exchange ──► order.cancel.queue
            │
    OrderCancelConsumer
      ├── cancelOrder(orderNo)
      │     ├── findByOrderNo → if status ≠ PENDING_PAYMENT → return (idempotent)
      │     ├── update status = CANCELLED
      │     ├── productMapper.increaseStock() × N items  (MySQL)
      │     └── stringRedisTemplate.increment()  × N items  (Redis)
      ├── basicAck on success
      └── basicNack(requeue=false) on failure
```

## New / Modified Files

### New
| File | Description |
|---|---|
| `mq/OrderCancelMessage.java` | `{ String orderId }` |
| `mq/OrderCancelConsumer.java` | `@RabbitListener(ORDER_CANCEL_QUEUE)`, idempotent, requeue=false |
| `docs/design/mq-order-adr.md` | ADR 513 tokens, covers M1/M2/M3, Method A vs B, consistency analysis |
| `test-m3.ps1` | PowerShell test suite (4 tests) |

### Modified
| File | Change |
|---|---|
| `config/RabbitMQConfig.java` | Add `ORDER_DELAY_QUEUE` / `ORDER_CANCEL_EXCHANGE` / `ORDER_CANCEL_QUEUE` beans; `@Value orderTimeoutMs` |
| `mapper/OrderMapper.java` | Add `findByOrderNo(String)` |
| `resources/mapper/OrderMapper.xml` | SQL for `findByOrderNo` |
| `mapper/ProductMapper.java` | Add `increaseStock(@Param id, @Param quantity)` |
| `resources/mapper/ProductMapper.xml` | SQL for `increaseStock` |
| `service/OrderService.java` | Add `cancelOrder(String orderNo)` |
| `service/impl/OrderServiceImpl.java` | Implement `cancelOrder()` + inject `OrderMapper` / `OrderItemMapper` |
| `service/impl/OrderPersistServiceImpl.java` | Change status → `PENDING_PAYMENT`; inject `RabbitTemplate`; send delay cancel message post-persist |
| `resources/application.yml` | Add `order.timeout-ms: 60000` |

## Test Results

| Test | Scenario | Result |
|---|---|---|
| Test 3 | order.delay.queue (TTL=60000) + order.cancel.queue (1 consumer) visible in RabbitMQ console | PASS |
| Test 4 | ADR word count ≥ 400 | PASS (513) |
| Test 1 | Place order → wait 65s → status=CANCELLED, MySQL stock +1, Redis stock +1, consistent | PASS |
| Test 2 | Place order → manually set PAID → wait 65s → status still PAID (idempotent) | PASS |

## Key Design Notes

- TTL injected via `@Value("${order.timeout-ms:1800000}")` — no hardcoded values
- `cancelOrder()` is `@Transactional`: MySQL restore + Redis restore in one unit of work
- `basicNack(requeue=false)` in cancel consumer: failed cancel messages are discarded, not looped
- Consumer uses default exchange (`""`) to send to delay queue — no extra exchange needed
- Method B (delayed-message-exchange plugin) documented in ADR as production alternative

## Production Improvement Notes (documented in ADR)

| Item | Current (Demo) | Production Recommendation |
|---|---|---|
| Consumer retry counter | `ConcurrentHashMap` (single-instance) | Redis `INCR order:retry:{orderId}` |
| Delay precision | Queue-level TTL (~100ms jitter) | Per-message delay via plugin or Redis ZSET |
| Transactional MQ send | Inside DB transaction (risk: MQ sent, DB rolled back) | Post-commit `ApplicationEvent` or RocketMQ transaction message |
