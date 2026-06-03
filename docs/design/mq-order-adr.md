# ADR: MQ-Based Order Processing — Async Flow, Reliable Delivery, and Timeout Cancellation

**Status:** Accepted  
**Date:** 2026-06-03  
**Author:** ShopWebsite Engineering

---

## Context

The order placement flow has three non-trivial concerns that must be addressed:

1. **Throughput**: A synchronous DB write on every `/api/orders` request becomes a bottleneck under load. The stock deduction must be atomic and fast; the heavy work (MySQL writes, inventory updates) should be async.
2. **Reliability**: MQ brokers can be temporarily unavailable. A message that is sent but never confirmed by the broker must be retried automatically, not silently dropped.
3. **Order lifecycle**: An order that stays in `PENDING_PAYMENT` indefinitely wastes reserved stock. A timeout mechanism should cancel unpaid orders and restore inventory.

---

## Decision: Three-Phase Design

### Phase M1 — Redis Lua Pre-Deduct + Async MQ

Stock deduction uses a Redis Lua script that atomically checks and decrements the counter. If the script returns `0` (insufficient stock) the request is rejected immediately with HTTP 400. If it succeeds, an `OrderMessage` (containing a pre-generated UUID and a price snapshot) is sent to `order.exchange` → `order.queue`. The HTTP response returns `{ status: "PROCESSING", orderId: "…" }` within milliseconds.

The `OrderConsumer` persists the order to MySQL inside a transaction and decrements the MySQL `stock` column as the durable record. A `UNIQUE KEY` on `order.order_no` acts as the last-resort idempotency guard.

### Phase M2 — Reliable Delivery + Idempotent Consumption

Before calling `rabbitTemplate.convertAndSend`, `OrderServiceImpl` writes a row to `mq_message` (status=0, pending). A `ConfirmCallback` on the `RabbitTemplate` updates the row to status=1 (delivered) on broker ACK, or status=2 (failed) on NACK. A `@Scheduled` job runs every 60 seconds and re-sends all rows with status=2 and `retry_count < 3`.

On the consumer side, `OrderConsumer` maintains an in-memory `ConcurrentHashMap<String, AtomicInteger>` for per-message retry counts. After three consecutive failures, it calls `basicNack(tag, false, false)` to route the message to `order.dlq` via the configured Dead Letter Exchange (DLX). `OrderDlqConsumer` marks the `mq_message` row as status=3 (dead) and emits a log-level `ERROR` alert.

### Phase M3 — Delayed Queue + Order Timeout Cancellation (this ADR)

#### Method A: TTL + DLX (chosen)

A dedicated `order.delay.queue` is declared with:

```
x-message-ttl  = ${order.timeout-ms}   (default 1 800 000 ms = 30 min)
x-dead-letter-exchange      = order.cancel.exchange
x-dead-letter-routing-key   = order.cancel.key
```

When `OrderPersistServiceImpl` successfully writes the order, it immediately sends an `OrderCancelMessage` to `order.delay.queue`. The TTL value is injected via `@Value("${order.timeout-ms:1800000}")` — no hard-coded numbers anywhere.

After the TTL elapses, RabbitMQ routes the expired message through `order.cancel.exchange` to `order.cancel.queue`. `OrderCancelConsumer` receives it and calls `OrderService.cancelOrder(orderNo)`, which:

1. Loads the order by `order_no`.
2. If status ≠ `PENDING_PAYMENT`, returns immediately (idempotent — the user may have already paid).
3. Updates status to `CANCELLED`.
4. Loads `order_item` rows and calls `productMapper.increaseStock` + `stringRedisTemplate.increment` for each item.
5. Logs the cancellation.

If `cancelOrder` throws, the consumer calls `basicNack(tag, false, false)` (requeue=false) to prevent an infinite retry loop.

#### Method B: RabbitMQ Delayed Message Plugin (not chosen)

The `rabbitmq_delayed_message_exchange` plugin allows per-message delay via a header (`x-delay`) on a custom exchange of type `x-delayed-message`. This avoids declaring a per-TTL queue and supports variable delay per message.

**Why not chosen:** The plugin requires manual installation on each broker node and is not available in the official `rabbitmq:3-management` Docker image without a custom build. For a self-contained demo that runs with `docker-compose up`, Method A (pure AMQP, no plugin) is more portable. In a managed cloud environment (e.g., AWS AmazonMQ), Method B would be the better choice because the plugin may be available and per-message granularity is valuable when different product categories have different payment windows.

---

## Consequences

| Concern | Outcome |
|---|---|
| Stock consistency | Redis counter restored atomically; MySQL stock restored in the same transaction as status update |
| Idempotency | `cancelOrder` is a no-op if status ≠ PENDING_PAYMENT; safe to call multiple times |
| No retry loop | `basicNack(requeue=false)` ensures dead messages don't loop in `order.cancel.queue` |
| Configurability | Timeout controlled by `order.timeout-ms` in `application.yml`; test uses 60 000 ms |
| Single-instance limit | `ConcurrentHashMap` retry counter in `OrderConsumer` is not distributed; production should use a Redis-backed counter |
| Schema | No migration needed for M3; `order.status` column already accepts any VARCHAR value |

---

## Status Values for `order.status`

| Value | Meaning |
|---|---|
| `PENDING_PAYMENT` | Order created, awaiting payment |
| `PAID` | Payment confirmed (set externally, outside this demo scope) |
| `CANCELLED` | Timed out or manually cancelled; stocks restored |
