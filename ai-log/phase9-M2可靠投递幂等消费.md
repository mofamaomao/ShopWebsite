# Phase 9 — M2: Reliable Delivery + Idempotent Consumption

## Objective

Reinforce message reliability on top of M1 async order flow:
- Producer: persist message to DB before sending, async confirm callback updates status
- Scheduler: retry failed messages every 60s
- Consumer: explicit idempotent check + retry count + DLQ routing
- DLQ Consumer: log alert + mark dead in mq_message

## Architecture

```
OrderServiceImpl
  ├── Redis Lua pre-deduct
  ├── mqMessageService.save(status=0)   ← new: DB-first guarantee
  └── orderProducer.send() [async]
         └── ConfirmCallback
               ├── ack  → markDelivered(status=1)
               └── nack → markFailed(status=2, retry_count++)

OrderRetryScheduler (@Scheduled 60s)
  └── findForRetry (status=2, retry_count<3) → resend

OrderConsumer
  ├── isProcessed() → ACK fast-path (idempotent)
  ├── persist() success → ACK
  └── persist() fail → retries++ → requeue=true(<3) / requeue=false(>=3) → DLQ

OrderDlqConsumer
  └── markDead(status=3) + log alert
```

## New / Modified Files

### New
| File | Description |
|---|---|
| `entity/MqMessage.java` | Entity with status constants (0/1/2/3) |
| `mapper/MqMessageMapper.java` | insert / updateStatus / markFailed / markDead / findForRetry |
| `resources/mapper/MqMessageMapper.xml` | SQL mappings |
| `service/MqMessageService.java` | Interface |
| `service/impl/MqMessageServiceImpl.java` | Implementation |
| `mq/OrderRetryScheduler.java` | @Scheduled(fixedDelay=60000) retry |
| `mq/OrderDlqConsumer.java` | DLQ consumer, markDead + log |
| `docs/migration_m2.sql` | CREATE TABLE mq_message |
| `test-m2.ps1` | PowerShell automated test suite |

### Modified
| File | Change |
|---|---|
| `ShopApplication.java` | Added @EnableScheduling |
| `config/RabbitMQConfig.java` | ConfirmCallback + ReturnsCallback in RabbitTemplate |
| `mq/OrderProducer.java` | void send(), removed sync confirm wait |
| `mq/OrderConsumer.java` | isProcessed() fast-path + ConcurrentHashMap retry count |
| `service/OrderPersistService.java` | Added isProcessed() |
| `service/impl/OrderPersistServiceImpl.java` | Implemented isProcessed() |
| `service/impl/OrderServiceImpl.java` | Writes mq_message before send; inject ObjectMapper + MqMessageService |

## Test Results

| Test | Scenario | Result |
|---|---|---|
| Test 1 | Normal order: mq_message status 0→1 | PASS (status=1, retry_count=0) |
| Test 3 | Idempotent: duplicate message, 1 order row | PASS (count=1 after re-publish) |
| Test 5 | mq_message distribution: all status=1 | PASS (2 records, both delivered) |
| Test 2 | MQ down → restart → scheduler retry | Manual (requires docker stop/start) |
| Test 4 | 3 failures → DLQ → [DLQ] log line | Verified via debug session |

## Debug Session Record

| Issue | Root Cause | Fix |
|---|---|---|
| mq_message empty, orders 200 | App running M1 code (not restarted after M2 build) | `mvn clean spring-boot:run` |
| All messages → status=3 (DLQ) | MySQL product stock = 0 from prior test runs | `UPDATE product SET stock = 100 WHERE id = 1` |
| DLQ Consumer fires on startup | Old DLQ messages from M1-era tests consumed on restart | `DELETE FROM mq_message` to clear stale records |
| Test 1 FAIL despite mq_message=3 | Switch default message was misleading ("No record" when record existed with status=3) | Added explicit status=3 branch in test script |
| PowerShell parse error | Chinese strings in .ps1 → GBK encoding breaks syntax | Rewrote script in ASCII-only English |

## Key Design Notes

- `mq_message.id = orderId (UUID)` — same as `order.order_no`, enables join-free lookup
- `ConfirmCallback` runs in RabbitMQ async thread; no @Transactional needed for markDelivered/markFailed
- Consumer retry uses in-memory `ConcurrentHashMap` (single-instance demo; production: Redis counter)
- `requeue=false` after 3 retries ensures messages don't loop infinitely in order.queue
- DLQ Consumer does NOT re-throw — silent consumption with log + DB mark is intentional
