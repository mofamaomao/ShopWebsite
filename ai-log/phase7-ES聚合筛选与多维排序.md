# Phase 7 归档 — ES 聚合筛选与多维排序（E3）

**日期：** 2026-06-02  
**分支：** claude/jolly-edison-MpzBv

---

## 目标

在 E1/E2 全文搜索基础上完成 E3：

- **Bool Query 扩展**：keyword→must(multiMatch)，category→filter(term)，price→filter(range)
- **Terms Aggregation**：与搜索同请求返回分类计数，驱动前端侧边栏
- **多维排序**：price_asc / price_desc / sales_desc（co.elastic.clients 原生 SortOptions API）
- **统一响应结构**：`SearchResultVO {products, total, categoryBuckets}`
- **参数校验**：sort 枚举（400），minPrice/maxPrice 非负且 min≤max（400）
- **前端改造**：排序选择器、价格区间输入、分类侧边栏（点击切换/取消）
- **ADR 文档**：`docs/design/es-search-adr.md`（≥350字，含设计决策与实测数据）

---

## Prompt 原文（E3）

```
角色：你是一名 Java 后端工程师 + Vue 前端工程师。

GET /api/products 新增以下参数（全部可选，可自由组合）：
  category   - 分类精确筛选
  minPrice   - 最低价（含）
  maxPrice   - 最高价（含）
  sort       - 枚举：price_asc / price_desc / sales_desc / 空字符串（默认相关性）

ES 查询结构：
  Bool Query：
    must: multiMatch(name^2+description)  或 matchAll（无 keyword 时）
    filter: term(category)、range(price)

Terms Aggregation：
  与搜索同一 NativeQuery，聚合名 "category_count"，field="category"，size=20
  
统一返回结构：
  {code:200, data:{products:[...], total:128, categoryBuckets:[{category:'手机', count:42}]}}

校验：
  sort 非法值 → 400
  minPrice/maxPrice 为负 → 400
  minPrice > maxPrice → 400

前端：
  排序选择器（el-select）
  价格区间输入（两个 el-input）
  分类侧边栏（来自 categoryBuckets，点击筛选，再点取消）
  v-html 高亮保留

ADR：docs/design/es-search-adr.md，≥350字，记录 filter context 选择理由、聚合方案、性能数据
```

---

## 新增 / 修改文件

### 新增文件

| 文件 | 说明 |
|------|------|
| `vo/SearchResultVO.java` | 统一响应 `{products, total, categoryBuckets}` |
| `vo/CategoryBucketVO.java` | 分类聚合桶 `{category, count}` |
| `docs/design/es-search-adr.md` | 设计决策记录，含 filter context 理由与实测性能 |

### 修改文件

| 文件 | 变更内容 |
|------|---------|
| `service/ProductSearchService.java` | `search()` 签名扩展 category/minPrice/maxPrice/sort 参数，返回 `SearchResultVO` |
| `service/impl/ProductSearchServiceImpl.java` | Bool Query + Terms Agg + SortOptions 完整实现 |
| `service/ProductService.java` | `listProducts()` 签名扩展，返回 `SearchResultVO` |
| `service/impl/ProductServiceImpl.java` | 路由扩展（有任意 ES 参数即走 ES）+ 参数校验 |
| `controller/ProductController.java` | 新增 category/minPrice/maxPrice/sort 四个参数 |
| `shop-frontend/src/views/HomeView.vue` | 排序器 + 价格区间 + 分类侧边栏，`data.products` 替换 `data.list` |

---

## 关键实现

### Bool Query 构建

```java
List<Query> mustClauses = new ArrayList<>();
List<Query> filterClauses = new ArrayList<>();

if (keyword != null && !keyword.isBlank()) {
    mustClauses.add(Query.of(q -> q.multiMatch(mm -> mm
            .query(keyword).fields(List.of("name^2", "description"))
            .type(TextQueryType.BestFields))));
} else {
    mustClauses.add(Query.of(q -> q.matchAll(ma -> ma)));
}

if (category != null && !category.isBlank()) {
    filterClauses.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
}

if (minPrice != null || maxPrice != null) {
    filterClauses.add(buildPriceRangeFilter(minVal, maxVal));
}

Query finalQuery = Query.of(q -> q.bool(b -> b.must(mustClauses).filter(filterClauses)));
```

### 价格 Range Filter（co.elastic.clients 8.13.4 使用 JsonData）

```java
private Query buildPriceRangeFilter(Double minVal, Double maxVal) {
    return Query.of(q -> q.range(r -> {
        r.field("price");
        if (minVal != null) r.gte(JsonData.of(minVal));
        if (maxVal != null) r.lte(JsonData.of(maxVal));
        return r;
    }));
}
```

### Terms Aggregation + 读取

```java
// 构建（同一 NativeQuery）
.withAggregation("category_count",
        Aggregation.of(a -> a.terms(t -> t.field("category").size(20))))

// 读取
// ⚠️ .aggregation() 返回 Spring 包装类，需再调 .getAggregate() 才到 co.elastic.clients Aggregate
catAgg.aggregation().getAggregate().sterms().buckets().array().forEach(b -> {
    vo.setCategory(b.key().stringValue());
    vo.setCount(b.docCount());
});
```

### 排序（SortOptions 原生 API）

```java
return switch (sort) {
    case "price_asc"  -> List.of(SortOptions.of(s -> s.field(f -> f.field("price").order(SortOrder.Asc))));
    case "price_desc" -> List.of(SortOptions.of(s -> s.field(f -> f.field("price").order(SortOrder.Desc))));
    case "sales_desc" -> List.of(SortOptions.of(s -> s.field(f -> f.field("sales").order(SortOrder.Desc))));
    default -> Collections.emptyList();
};
```

---

## 踩坑记录

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 1 | `catAgg.aggregation().sterms()` 编译报错 | `ElasticsearchAggregation.aggregation()` 返回 Spring 的 `org.springframework.data.elasticsearch.client.elc.Aggregation` 包装类，不是 co.elastic.clients 的 `Aggregate` | 改为 `.aggregation().getAggregate().sterms()` |
| 2 | Windows cmd 测试中文参数返回 Tomcat HTML 400 | cmd 不 URL 编码中文，Tomcat 10 拒绝非 ASCII 字符（E2 阶段同一问题） | 使用 URL 编码（`手机`→`%E6%89%8B%E6%9C%BA`）或 PowerShell `Invoke-RestMethod` |

---

## 验收结果

| 验收项 | 结果 |
|--------|------|
| `keyword=手机`：返回 `categoryBuckets` 含分类计数 | ✅ |
| `category=手机`：仅返回手机类商品 | ✅ |
| `sort=price_asc`：商品按价格升序排列 | ✅ |
| `minPrice=100&maxPrice=5000`：价格区间过滤正确 | ✅ |
| `sort=invalid`：返回 JSON 400 + 错误信息 | ✅ |
| 无任何筛选参数：MySQL 路径，`categoryBuckets=[]` | ✅ |
| 前端侧边栏：有搜索结果时渲染，点击筛选/取消 | ✅ |
| ADR 文档：`docs/design/es-search-adr.md` | ✅ |
| 编译通过（`mvn compile -q` 无报错） | ✅ |

---

## 遗留说明

1. `sales` 字段固定为 0，`sales_desc` 排序暂无实际区分效果（需下单回写 ES）
2. 价格用 `double` 传输，高精度场景需改 `scaled_float` 或 `long`（分为单位）
3. 多实例 Caffeine 缓存广播、`sync_fail_log` 定时重试——Phase 6 遗留，未处理
