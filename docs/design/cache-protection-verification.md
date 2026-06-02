# R2 三级缓存防护策略 — 验证记录

## 防线一：缓存穿透（布隆过滤器）

### 验证命令
```bash
# 请求一个不存在的商品 ID
curl -s http://localhost:8080/api/products/99999 | jq .
```

### 预期日志输出
```
INFO  c.s.s.i.ProductServiceImpl - Bloom Filter 拦截，商品不存在 id=99999
```

### 预期响应
```json
{"code":1004,"msg":"商品不存在","data":null}
```

### 验证要点
- 日志出现 "Bloom Filter 拦截" 字样
- DB 查询日志（MyBatis SQL 日志）**无任何 SELECT 语句**
- 响应耗时 < 5ms（无 DB IO）

---

## 防线二：缓存击穿（分布式互斥锁重建）

### 验证步骤
```bash
# 1. 先请求一次，预热缓存
curl -s http://localhost:8080/api/products/1

# 2. 手动删除 Redis 中的热点 key
redis-cli DEL "product:detail:1"

# 3. 并发 10 个请求同时打入
for i in $(seq 1 10); do
  curl -s http://localhost:8080/api/products/1 &
done; wait
```

### 预期日志输出
```
INFO  c.s.s.i.ProductServiceImpl - DB 查询商品 id=1       ← 仅出现 1 次
DEBUG c.s.s.i.ProductServiceImpl - Double-check Redis 命中 id=1  ← 出现 ~9 次
```

### 验证要点
- "DB 查询商品 id=1" 日志**只出现 1 次**（其余 9 个请求命中 Double-check）
- 无 Deadlock 日志
- 10 个请求均返回正确商品数据

---

## 防线三：缓存雪崩（随机 TTL）

### 验证步骤
```bash
# 批量写入 100 个商品缓存（先确保商品存在）
for i in $(seq 1 100); do
  curl -s http://localhost:8080/api/products/$i > /dev/null
done

# 抽查 10 个 key 的 TTL
for i in 1 10 20 30 40 50 60 70 80 90; do
  echo -n "product:detail:$i TTL = "
  redis-cli TTL "product:detail:$i"
done
```

### 预期输出（TTL 值各不相同，均在 1800~2100 之间）
```
product:detail:1  TTL = 1923
product:detail:10 TTL = 2047
product:detail:20 TTL = 1856
product:detail:30 TTL = 2091
product:detail:40 TTL = 1987
product:detail:50 TTL = 1834
product:detail:60 TTL = 2012
product:detail:70 TTL = 1901
product:detail:80 TTL = 2076
product:detail:90 TTL = 1968
```

### 验证要点
- 所有 TTL 值在 `1800 ~ 2100`（base 1800s + jitter 0~300s）范围内
- **10 个 TTL 值各不相同**（随机抖动有效）

---

## 本地二级缓存（Caffeine）验证

```bash
# 快速连续请求同一商品（5s 内），观察日志
curl -s http://localhost:8080/api/products/1
curl -s http://localhost:8080/api/products/1
curl -s http://localhost:8080/api/products/1
```

### 预期日志
```
DEBUG c.s.s.i.ProductServiceImpl - Redis cache 命中 id=1   ← 第 1 次（Caffeine 冷启动）
DEBUG c.s.s.i.ProductServiceImpl - Local cache 命中 id=1   ← 第 2、3 次
```
