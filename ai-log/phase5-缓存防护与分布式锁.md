# Phase 5 归档 — 缓存防护层 & 分布式锁迁移

**日期：** 2026-06-02
**分支：** claude/cool-wozniak-CEti2 → 合并至 claude/jolly-edison-MpzBv

---

## 目标

在已有电商 Demo 基础上完成两项后端加固：

- **R3**：将下单接口的 `SELECT FOR UPDATE` DB 行锁迁移至 Redisson 分布式锁，消除死锁风险并支持水平扩展。
- **R2**：为商品详情接口构建三级缓存防护层（缓存穿透 / 击穿 / 雪崩），并加入 Caffeine 本地二级缓存。

---

## Prompt 原文（R3）

```
你是一名 Java 后端工程师，负责将下单接口的 SELECT FOR UPDATE 行锁
迁移到 Redisson 分布式锁，并输出一份 ADR 文档。

新逻辑（Redisson 分布式锁，锁粒度：用户维度）：
  String lockKey = RedisKeyConstants.ORDER_LOCK + userId;
  RLock lock = redissonClient.getLock(lockKey);
  boolean acquired = lock.tryLock(3, 10, TimeUnit.SECONDS);
  if (!acquired) throw new BusyException("系统繁忙，请稍后重试");
  try {
    // 库存检查 / 写订单 / 扣库存（AND stock>=?）
  } finally {
    if (lock.isHeldByCurrentThread()) lock.unlock();
  }

约束：
- tryLock 等待时间=3s，leaseTime=10s，不允许使用 lock()
- finally 中必须判断 isHeldByCurrentThread() 再 unlock
- 库存扣减 SQL 必须带 AND stock >= qty 的乐观检查
```

## Prompt 原文（R2）

```
你是一名 Java 后端工程师，正在为电商 Demo 加固缓存防护层。

必须实现的三道防线：
防线一：缓存穿透 — 布隆过滤器（RBloomFilter，启动时加载全量 productId）
防线二：缓存击穿 — 分布式互斥锁重建（tryLock + double-check）
防线三：缓存雪崩 — 随机 TTL（baseTTL + Random(0,300)）
可选：本地二级缓存（Caffeine，500条/5s TTL）

验收标准：
- 穿透：请求 id=99999，日志显示"Bloom Filter 拦截"，DB 无查询
- 击穿：DEL 热点 key，并发 10 请求，DB 只查 1 次
- 雪崩：批量写 100 个缓存，redis-cli TTL 抽查 10 个，值各不相同
```

---

## AI 输出摘要

### R3 — 分布式锁迁移

1. **依赖**：`pom.xml` 新增 `redisson-spring-boot-starter 3.27.2`，复用已有 `spring.data.redis` 配置，零额外运维成本。

2. **OrderServiceImpl 重构**：
   - 移除 `productMapper.findByIdForUpdate()`（`SELECT FOR UPDATE`）
   - 入口处以 `userId` 粒度 `tryLock(3s wait, 10s lease)`
   - `finally` 块 `isHeldByCurrentThread()` 判断后 `unlock()`，防误解锁
   - 库存扣减保留 `AND stock >= qty` 乐观检查作为最后安全网

3. **常量**：`RedisKeyConstants` 新增 `ORDER_LOCK = "order:lock:"`。

4. **ErrorCode**：新增 `SYSTEM_BUSY(1006, "系统繁忙，请稍后重试")`。

5. **ADR 文档**：`docs/design/redis-lock-adr.md`，对比 DB 行锁 / Redis 分布式锁 / 乐观锁 CAS 三方案，记录 userId 粒度选型理由及后续风险（Redis 单点、Lettuce 冲突、leaseTime 调优）。

### R2 — 三级缓存防护

1. **新增依赖**：`caffeine`（Spring Boot 管理版本，无需写版本号）。

2. **RedisConfig**：提供 `RedisTemplate<String, Object>` Bean，使用 Jackson + DefaultTyping 序列化，支持反序列化回 `ProductVO`。

3. **CaffeineConfig**：`Cache<Long, ProductVO>` Bean，`maximumSize=500 / expireAfterWrite=5s`。

4. **CacheUtil**：封装 `setWithRandomTTL(key, value, baseTTL, unit)`，叠加 `ThreadLocalRandom.nextLong(0, 300)` 秒抖动。

5. **ProductServiceImpl 重构**（查询顺序 Local → Redis → DB）：
   - **防线一**：`@PostConstruct` 初始化 `RBloomFilter`（100000条/误判率1%），加载全量 `productId`；`bloomFilter.contains(id)` 为 false 直接抛 404，不查 DB；初始化失败 `catch` 置 `null` 降级。
   - **防线二**：Redis miss 后 `tryLock(3s, 10s)`，持锁后做 double-check 再查 DB，未拿到锁等 200ms 后降级读 Redis，再 miss 抛 `SYSTEM_BUSY`。
   - **防线三**：所有写缓存调用 `cacheUtil.setWithRandomTTL()`，TTL 落在 `[1800, 2100)` 秒区间。
   - **缓存一致性**：`evictProductCache(id)` 先删 Redis 再失效 Caffeine；新增商品时 `bloomFilter.add(id)`。

6. **验证文档**：`docs/design/cache-protection-verification.md`，记录三道防线的验证命令、预期日志输出和量化指标。

### 单元测试（22条，全部通过）

| 测试类 | 条数 | 覆盖内容 |
|--------|------|----------|
| `ProductServiceImplTest` | 11 | 穿透拦截/降级、Cache-Aside三级命中路径、击穿锁逻辑double-check、缓存一致性 |
| `BloomFilterInitTest` | 3 | 正常初始化、Redisson异常降级、DB查询异常降级 |
| `CacheUtilTest` | 8 | TTL区间验证、随机性验证（20次多值）、时间单位、重复5次稳定性 |

---

## 变更文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `shop-backend/pom.xml` | 修改 | 新增 redisson 3.27.2、caffeine |
| `common/RedisKeyConstants.java` | 修改 | 新增 PRODUCT_DETAIL_PREFIX / PRODUCT_LOCK_PREFIX / PRODUCT_BLOOM_FILTER / ORDER_LOCK |
| `common/ErrorCode.java` | 修改 | 新增 SYSTEM_BUSY(1006) |
| `config/RedisConfig.java` | 新增 | RedisTemplate<String,Object> Jackson 序列化 Bean |
| `config/CaffeineConfig.java` | 新增 | 本地缓存 Bean（500条/5s） |
| `util/CacheUtil.java` | 新增 | setWithRandomTTL() 随机 TTL 工具 |
| `service/impl/OrderServiceImpl.java` | 修改 | SELECT FOR UPDATE → Redisson userId 粒度锁 |
| `service/impl/ProductServiceImpl.java` | 修改 | 三级缓存防护全量重构 |
| `docs/design/redis-lock-adr.md` | 新增 | R3 ADR 文档 |
| `docs/design/cache-protection-verification.md` | 新增 | R2 验证记录 |
| `test/.../ProductServiceImplTest.java` | 新增 | 11条单元测试 |
| `test/.../BloomFilterInitTest.java` | 新增 | 3条单元测试 |
| `test/.../CacheUtilTest.java` | 新增 | 8条单元测试 |

---

## 验收结果

| 验收项 | 类型 | 结果 |
|--------|------|------|
| 商品详情缓存（Cache-Aside）Local→Redis→DB 三级查询 | 必须 | ✅ |
| 缓存穿透防护：布隆过滤器拦截，DB 无查询 | 必须 | ✅ |
| 缓存击穿防护：分布式锁 + double-check，DB 只查 1 次 | 必须 | ✅ |
| 缓存雪崩防护：TTL 随机抖动，批量写入不同时失效 | 必须 | ✅ |
| 缓存一致性：Cache-Aside delete 策略，双层缓存同时失效 | 必须 | ✅ |
| 多级缓存：Caffeine 本地 5s TTL + Redis 远程随机 TTL | 可选 | ✅ |
| 布隆过滤器初始化失败降级，不影响服务启动 | 约束 | ✅ |
| Redisson 分布式锁迁移，ORDER_LOCK userId 粒度 | 必须 | ✅ |
| 单元测试 22 条全部通过（BUILD SUCCESS） | 必须 | ✅ |
| 变更推送至 GitHub，合并至 claude/jolly-edison-MpzBv | 必须 | ✅ |

---

## 遗留问题

1. **Redis 单点风险**：当前 Demo 为单节点模式，生产环境需切换 Redis Sentinel/Cluster，并为 `tryLock` 添加降级策略（回退至 DB 行锁）。
2. **Redisson 与 Lettuce 共存**：`redisson-spring-boot-starter` 接管 `RedisConnectionFactory`，需集成测试验证 `CartServiceImpl` / `SeckillCacheServiceImpl` 的 `StringRedisTemplate` 操作不受影响。
3. **布隆过滤器删除商品未处理**：Bloom Filter 不支持删除，下架商品后过滤器仍包含该 ID，需结合定时任务全量重建或引入 Counting Bloom Filter。
4. **Caffeine 多实例广播**：多实例部署时本地缓存无法同步失效，需引入 Redis Pub/Sub 广播 `evict` 事件。
5. **缓存命中率监控**：现依赖 DEBUG 日志手动统计，后续可接入 Micrometer + Prometheus 实现自动采集。

---

## 截图

> 请将以下截图放入 ai-log/screenshots/phase5/ 目录：
> - [ ] `mvn test` 输出：`Tests run: 22, Failures: 0`
> - [ ] 请求 `/api/products/99999` 响应 404，日志含"Bloom Filter 拦截"
> - [ ] `redis-cli TTL product:detail:{1..10}` 输出（10个不同 TTL 值）
> - [ ] DEL 热点 key 后并发 10 请求，日志中"DB 查询"仅出现 1 次
