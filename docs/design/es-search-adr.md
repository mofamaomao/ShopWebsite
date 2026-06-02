# ADR-001：Elasticsearch 聚合筛选与多维排序设计决策

**状态：** Accepted  
**日期：** 2026-06-02  
**作者：** 后端工程组

---

## 背景与问题陈述

Phase 6（E1/E2）完成了 ES 全文搜索的基础集成：将 MySQL 商品数据同步至 ES，搜索关键词时走 ES multi_match，无关键词时降级 MySQL。验收结果良好，IK 中文分词准确，高亮标签正常渲染。

然而，单纯的关键词搜索满足不了真实电商场景：用户在搜索结果页通常需要按**分类**缩小范围，按**价格区间**过滤，按**价格高低**或**销量**排序。这三类需求构成 E3 的核心：

1. **聚合（Aggregation）**：在一次查询中同时返回分类维度的文档计数，驱动前端侧边栏动态渲染，避免额外的 count 请求。
2. **多维过滤（Filtering）**：category（精确匹配）、price range（区间过滤），必须走 `filter` 子句而非 `must`，不参与相关性计分，性能更好。
3. **动态排序（Sorting）**：price_asc / price_desc / sales_desc，覆盖 ES 默认的相关性排序（_score desc）。

---

## 决策内容

### 查询结构：Bool Query with Filter Context

选用 ES Bool Query，`must` 放全文检索，`filter` 放精确过滤：

```
bool
├─ must:   multiMatch(name^2 + description)  ← 影响评分
│          或 matchAll（无关键词时）
└─ filter: term(category)                    ← 不影响评分，可被缓存
           range(price: gte/lte)             ← 不影响评分
```

**选 `filter` 而非 `must` 的理由**：`filter` 子句结果由 ES 自动缓存（Filter Cache），重复查询同一 category 时直接走内存，无需重新计算 BM25 分值；`must` 子句每次都参与评分计算，在纯过滤场景下是性能浪费。

### 聚合：Terms Aggregation

在同一 NativeQuery 中附加 `terms` 聚合：

```java
Aggregation.of(a -> a.terms(t -> t.field("category").size(20)))
```

`category` 字段类型为 `keyword`，无需分词，terms 聚合直接对倒排索引的 ordinals 操作，开销极低。`size(20)` 上限足够覆盖所有商品分类（当前 6 个）。

聚合结果通过 `ElasticsearchAggregations` 读取：

```java
ElasticsearchAggregations aggs = (ElasticsearchAggregations) hits.getAggregations();
catAgg.aggregation().sterms().buckets().array()  // → List<StringTermsBucket>
```

统一封装为 `CategoryBucketVO {category, count}` 随搜索结果一并返回，前端无需二次请求。

### 排序：SortOptions API

使用 co.elastic.clients 原生 `SortOptions`，不走 Spring Data Sort 抽象（后者无法精细控制 missing/unmapped_type 等 ES 特有语义）：

```java
SortOptions.of(s -> s.field(f -> f.field("price").order(SortOrder.Asc)))
```

排序枚举：`price_asc` / `price_desc` / `sales_desc` / 空字符串（默认相关性）。

### 路由策略

```
有 keyword / category / minPrice / maxPrice / 非空 sort → ES
否则 → MySQL（兜底，categoryBuckets 返回空列表）
source=mysql 参数 → 强制 MySQL（性能对比用）
```

ES 路径任意异常均降级 MySQL，不影响主流程。

### 统一响应结构

由原 `PageVO<ProductVO>` 改为 `SearchResultVO`：

```json
{
  "products": [...],
  "total": 128,
  "categoryBuckets": [
    { "category": "手机", "count": 3 },
    { "category": "电脑", "count": 2 }
  ]
}
```

MySQL 降级路径也返回相同结构，`categoryBuckets` 为空列表，前端侧边栏不渲染。

---

## 备选方案分析

| 方案 | 优点 | 放弃原因 |
|------|------|---------|
| 分类过滤走 must | 无需改动 | 影响评分、无法走 filter cache |
| 单独发 /api/products/categories 聚合接口 | 前后端职责分离 | 两次 HTTP 往返，且数据不与当前过滤上下文同步 |
| 前端静态写死分类列表 | 实现最简单 | 分类增删需改代码，无法反映实际有数据的分类 |
| Spring Data Sort 抽象 | 代码量少 | 无法直接用 `SortOptions` 控制排序细节；且未来需 missing 处理时会受限 |

---

## 性能数据（实测）

测试环境：本地 Windows，ES 8.13.0 + IK，MySQL 8，商品数据 12 条（Phase 6 结束时扩充至 12 条种子数据）。

| 查询类型 | 暖均值 | P99 |
|---------|--------|-----|
| ES keyword 搜索（E2 基准）| 53ms | 57ms |
| ES keyword + category filter | ~55ms | ~60ms |
| ES keyword + price range | ~54ms | ~58ms |
| ES keyword + agg（同一请求）| ~56ms | ~62ms |
| MySQL LIKE（兜底）| 47ms | 59ms |

> 12 条数据规模下 ES 与 MySQL 仍持平。加 filter/agg 后增量 < 5ms，原因是 filter cache 命中率高、terms agg 在 keyword 字段上开销极低。规模到万级以上，ES 倒排索引优势会明显拉开差距。

---

## 后果与遗留事项

**正面**
- 一次 HTTP 请求同时返回过滤结果 + 分类聚合，前端体验流畅
- `filter` 上下文自动缓存，高频同类查询性能持续提升
- 排序由后端统一管控，枚举校验防止非法参数注入

**遗留/已知限制**
- `sales` 字段当前固定为 0（下单后未回写 ES），`sales_desc` 排序暂无实际效果
- 价格区间使用 `JsonData.of(double)` 传递，精度受 double 浮点限制；高精度场景需改用 `scaled_float` 或 `long`（分为单位）
- 多实例部署时本地 Caffeine 缓存失效广播问题（Phase 6 遗留）依然存在
- `sync_fail_log` 无定时重试，双写失败需人工干预
