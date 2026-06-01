# ADR-001：下单接口由 DB 行锁迁移至 Redisson 分布式锁

- **状态**：已采纳
- **日期**：2026-06-01
- **作者**：后端团队

---

## 背景

ShopWebsite 的 `OrderServiceImpl.createOrder()` 方法原先通过 `SELECT ... FOR UPDATE` 对 `product` 表的目标行加悲观行锁，以防止并发下单时超卖。这一机制在单节点、低并发场景下运行稳定，但随着业务发展暴露出以下问题：

1. **锁持有时间过长**：`SELECT FOR UPDATE` 在整个事务生命周期内持有行锁。当事务中包含写订单、写订单明细等多条 INSERT 时，锁持有时间远超库存检查本身所需，造成 MySQL InnoDB 行锁争抢加剧，TPS 下降明显。
2. **死锁风险**：用户可同时购买多个商品，若两个并发请求以不同顺序对多行加锁，极易触发 MySQL deadlock（已在压测日志中观察到 `Deadlock found when trying to get lock; try restarting transaction`）。
3. **不适合水平扩展**：应用部署多实例时，DB 行锁仍能保证正确性，但所有并发压力都落在 MySQL 上，成为单点瓶颈，无法通过加应用实例缓解。
4. **秒杀模块已引入 Redis**：项目中 `SeckillCacheServiceImpl` 和令牌桶限流均依赖 Redis，基础设施已就绪，迁移成本低。

综合以上原因，决定将普通下单的防超卖机制迁移至 Redisson 分布式锁，并保留 DB 层乐观检查作为最后一道防线。

---

## 决策

在 `createOrder()` 入口处以 **userId 为粒度** 获取 Redisson 可重入锁（`RLock`），参数设置为：

- `waitTime = 3s`：超出等待时间直接返回"系统繁忙"，避免线程堆积；
- `leaseTime = 10s`：看门狗自动续期上限，防止业务异常时锁永不释放；
- 禁止使用无参 `lock()`（无限等待，在高并发下会导致线程池耗尽）。

原 `findByIdForUpdate` 替换为普通 `findById`，去除 DB 行锁。库存扣减 SQL 保留 `AND stock >= qty` 条件，作为乐观检查的最后安全网。

---

## 对比方案

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **DB 行锁（SELECT FOR UPDATE）** | 实现简单，强一致，无额外依赖 | 锁粒度粗（整个事务），高并发易死锁，MySQL 成为瓶颈 | 低并发、单体应用、对 Redis 零依赖场景 |
| **Redis 分布式锁（Redisson，本方案）** | 锁粒度细、持有时间短；Redis 高吞吐；支持多实例水平扩展；tryLock 快速失败保护线程池 | 引入 Redis 单点故障风险（需主从/哨兵/集群）；网络分区时存在锁失效窗口 | 中高并发、已有 Redis 基础设施、多实例部署 |
| **乐观锁 CAS（version 字段）** | 无锁竞争，读性能极好；实现无需额外中间件 | 高并发写冲突时大量重试，CPU 飙升；需在 `product` 表加 `version` 列并改造所有写入路径，改造成本高 | 读多写少、冲突概率极低的场景（如用户资料更新） |

**选择 userId 粒度而非 productId 粒度的原因**：同一用户在短时间内连续下单（重复点击、网络抖动重试）的概率远高于两个不同用户同时抢同一商品。以 productId 为粒度会使热门商品成为锁热点，所有购买该商品的用户串行等待，吞吐下降更严重。userId 粒度将锁冲突控制在单用户维度，绝大多数用户互不影响。

---

## 结论

迁移后的核心变化：

1. `pom.xml` 新增 `redisson-spring-boot-starter 3.27.2`，复用已有 `spring.data.redis` 配置，零额外运维成本。
2. `OrderServiceImpl` 注入 `RedissonClient`，在方法入口 `tryLock(3, 10, TimeUnit.SECONDS)`，`finally` 块中 `isHeldByCurrentThread()` 判断后再 `unlock()`，防止误解锁他人持有的锁。
3. `ProductMapper.findByIdForUpdate` 替换为 `findById`，彻底移除 InnoDB 行锁，消除 deadlock 根源。
4. `decreaseStock` 的 `AND stock >= qty` 保留，确保即使锁异常失效，DB 层也不会出现负库存。

---

## 后续风险

1. **Redis 单点故障**：当前配置为单节点 Demo 模式。若 Redis 宕机，`RedissonClient.getLock()` 抛出连接异常，下单接口全部报错。生产环境须切换为 Redis Sentinel 或 Cluster 模式，并为 `tryLock` 添加降级策略（如退化至 DB 行锁）。
2. **Redisson 与 Spring Data Redis 的 Lettuce 客户端冲突**：`redisson-spring-boot-starter` 默认接管 `RedisConnectionFactory`，可能与项目中 `StringRedisTemplate`（Lettuce）的连接池配置产生冲突，需在集成测试中验证 `CartServiceImpl`、`SeckillCacheServiceImpl` 的 Redis 操作仍正常。
3. **锁粒度评估**：若未来引入购物车批量下单（一次下单数十个 SKU），userId 粒度锁的持有时间会随 SKU 数量线性增长，此时应评估是否拆分为每个 SKU 独立加锁 + Lua 原子扣减的组合方案。
4. **leaseTime 调优**：当前 10s 是保守估计，需在生产环境通过 APM 监控 `createOrder` P99 耗时，若远低于 10s 可适当缩短，减少锁泄漏窗口。
