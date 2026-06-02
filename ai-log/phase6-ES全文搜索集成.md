# Phase 6 归档 — Elasticsearch 全文搜索集成

**日期：** 2026-06-02
**分支：** claude/jolly-edison-MpzBv

---

## 目标

在已有电商 Demo 基础上完成 Elasticsearch 集成（E1 + E2）：

- **E1-Step2**：设计 `product` 索引 Mapping，支持 IK 中文分词（本地回退为 standard）。
- **E1-Step3**：Spring Data ES 集成，`ProductDocument` 实体映射。
- **E1-Step4a**：`POST /api/admin/es/init` 批量将 MySQL 商品同步至 ES。
- **E1-Step4b**：ProductService 写操作双写 ES，失败只记日志和 `sync_fail_log`，不影响主流程。
- **E2-Step1**：搜索接口迁移，keyword 走 ES multi_match，无 keyword 走 MySQL 兜底。
- **E2-Step3**：高亮返回，`<em class='search-hl'>` 标签，前端 `v-html` 渲染。
- **E2-Step4**：ES vs MySQL LIKE 性能对比实测。

---

## Prompt 原文（E1）

```
你是一名 Java 后端工程师，正在为电商 Demo 集成 Elasticsearch 全文搜索。

Step 2 — 创建 product 索引 Mapping，字段规范：
  name / description: text, analyzer=ik_max_word, search_analyzer=ik_smart
  category: keyword
  price: double
  stock / sales: integer
  image_url: keyword, index=false
  created_at: date
  约束：Mapping 保存在 resources/es/product-mapping.json

Step 3 — Spring Data ES 集成：
  pom.xml 新增 spring-boot-starter-data-elasticsearch
  ProductDocument.java: price 用 Double，不用 BigDecimal
  @Document(indexName = EsConstants.PRODUCT_INDEX)

Step 4a — POST /api/admin/es/init，批量从 MySQL 同步到 ES，无需鉴权

Step 4b — 双写同步：
  双写失败只记 ERROR 日志并写 sync_fail_log 表，不抛异常，不影响主流程

约束：
- 所有 ES 操作在 ProductSearchService 中
- entity→doc 转换在 EsConverter 中
- 不硬编码索引名（使用 EsConstants 常量）
- Mapping JSON 在 classpath，不用 Java 代码定义
```

## Prompt 原文（E2）

```
Step 1 — 搜索接口迁移
改造 GET /api/products?keyword=&page=1&size=10：
  有 keyword → 走 ES multi_match 查询
  无 keyword → 走 MySQL 全量分页（原逻辑保留作兜底）

ES 查询：MultiMatch name^2 + description，type=BEST_FIELDS
keyword 长度校验 ≤50 字

Step 3 — 高亮配置
preTags = "<em class='search-hl'>"，postTags = "</em>"
SearchHit.getHighlightField("name") → ProductVO.highlightName
前端 v-html="item.highlightName || item.name"

Step 4 — 性能对比写入 README，数据来自实测
```

---

## AI 输出摘要（E1）

### 新增文件

1. **`resources/es/product-mapping.json`**：索引 Mapping，包含 settings（IK 分析器定义）+ mappings（7个字段）。

2. **`common/EsConstants.java`**：`PRODUCT_INDEX = "product"` 常量，全局唯一索引名来源。

3. **`common/EsConverter.java`**：`toDocument(Product)` + `toVO(ProductDocument)` 静态工具。

4. **`entity/ProductDocument.java`**：`@Document(indexName = EsConstants.PRODUCT_INDEX, createIndex = false)`，`price = Double`，`createdAt = Long + @Field(type=Long)`。

5. **`repository/ProductSearchRepository.java`**：`ElasticsearchRepository<ProductDocument, Long>`，独立 `repository` 包（避开 `@MapperScan`）。

6. **`entity/SyncFailLog.java` + `mapper/SyncFailLogMapper.java`**：双写失败审计表，`@Insert` 注解写入。

7. **`service/ProductSearchService.java` / `impl/ProductSearchServiceImpl.java`**：
   - `bulkInit(List<Product>)`：批量 `saveAll`
   - `syncSave(Product)`：单条 upsert，异常 → log ERROR + `writeFailLog`
   - `syncDelete(Long)`：按 ID 删除，异常 → log ERROR + `writeFailLog`
   - `search(keyword, page, size)`：NativeQuery multi_match + HighlightQuery

8. **`controller/EsAdminController.java`**：`POST /api/admin/es/init`，返回同步条数。

9. **`config/RedissonConfig.java`**：手动创建 `RedissonClient` Bean，密码为空时跳过 `setPassword()`。

10. **`docs/migration_es.sql`**：`CREATE TABLE IF NOT EXISTS sync_fail_log`。

### 修改文件（E1 + E2）

- **`pom.xml`**：新增 `spring-boot-starter-data-elasticsearch`
- **`application.yml`**：新增 `spring.elasticsearch.uris`
- **`vo/ProductVO.java`**：新增 `highlightName` 字段
- **`service/ProductService.java`**：新增 `source` 参数 + createProduct/updateProduct/deleteProduct
- **`service/impl/ProductServiceImpl.java`**：keyword 路由 ES，`source=mysql` 强制 MySQL，ES 异常自动降级
- **`controller/ProductController.java`**：新增 `source` 参数
- **`config/SecurityConfig.java`**：`/api/admin/es/init` 加入 permitAll
- **`views/HomeView.vue`**：`v-html="p.highlightName || p.name"` + `.search-hl` 高亮样式

---

## 报错解决记录（E1）

| # | 报错关键信息 | 原因 | 解决方案 |
|---|------------|------|----------|
| 1 | `ConflictingBeanDefinitionException: productSearchRepository` | `ProductSearchRepository` 在 `com.shop.mapper` 包，`@MapperScan` 把它当 MyBatis Mapper 注册，与 Spring Data ES 工厂 Bean 冲突 | 移至新包 `com.shop.repository` |
| 2 | `ERR AUTH called without any password configured` | `spring.data.redis.password` 默认空字符串，Redisson 仍发 `AUTH ""`，本地 Redis 无密码拒绝 | 新增 `RedissonConfig`，密码为空时不调用 `setPassword()` |
| 3 | `mapper_parsing_exception: analyzer [ik_smart] has not been configured` | IK 未安装，Spring Data ES 启动时自动建索引失败 | 加 `createIndex = false`；临时改用 `standard` 分析器 |
| 4 | `Unsupported type 'Long' for date property 'createdAt'` | `@Field(type=FieldType.Date)` 与 Java `Long` 类型不匹配 | 改为 `@Field(type=FieldType.Long)` |
| 5 | `NativeQuery` import 编译报错 | `NativeQuery` 在 `client.elc` 包而非 `core.query` | import 改为 `org.springframework.data.elasticsearch.client.elc.NativeQuery` |
| 6 | `HighlightParameters cannot be converted to HighlightFieldParameters` | `HighlightField` 构造参数类型为 `HighlightFieldParameters`，非 `HighlightParameters` | 改用 `HighlightFieldParameters.builder()` |

---

## IK 插件安装记录

### 背景
ES 8.13.0 默认无中文分词，`standard` 分析器按字切割（`手机`→`手`+`机`），导致 `机械键盘` 被误召回。

### 踩坑过程

| # | 尝试 | 结果 | 原因 |
|---|------|------|------|
| 1 | `docker exec es bin/elasticsearch-plugin install <GitHub URL>` | 404 FileNotFoundException | GitHub releases 中国境内访问受限 |
| 2 | `docker exec es bin/elasticsearch-plugin install file:///tmp/analysis-ik.zip`（无 `--batch`）| `unable to read from standard input` 回滚失败 | 插件需要权限确认，`docker exec` 无 TTY，无法交互 |
| 3 | Infinilabs 官方 CDN 下载 + `docker cp` + `--batch` 安装 | **成功** ✅ | — |

### 最终安装命令
```powershell
# 1. Windows 下载
Invoke-WebRequest -Uri "https://release.infinilabs.com/analysis-ik/stable/elasticsearch-analysis-ik-8.13.0.zip" -OutFile "$env:TEMP\analysis-ik.zip"

# 2. 复制进容器
docker cp "$env:TEMP\analysis-ik.zip" es:/tmp/analysis-ik.zip

# 3. 静默安装（--batch 跳过权限确认交互）
docker exec es bin/elasticsearch-plugin install --batch file:///tmp/analysis-ik.zip
docker restart es
```

### 安装后重建索引
```bash
curl -X DELETE http://localhost:9200/product
curl -X PUT http://localhost:9200/product -H "Content-Type: application/json" -d @shop-backend/src/main/resources/es/product-mapping.json
curl -X POST http://localhost:8080/api/admin/es/init
```

### 验证结果
```json
# GET /_analyze {"analyzer":"ik_max_word","text":"苹果手机"}
{"tokens":[{"token":"苹果"},{"token":"手机"}]}
```
`苹果手机` → `["苹果", "手机"]`，中文词语正确切分 ✅

---

## 验收结果（E1 + E2）

| 验收项 | 结果 |
|--------|------|
| 建索引返回 `acknowledged: true` | ✅ |
| `POST /api/admin/es/init` 返回 `{"code":200,"data":5}` | ✅ |
| `_count` 返回 5 | ✅ |
| 搜索"手机"返回含苹果手机的商品，不报错 | ✅ |
| `highlightName` 含 `<em class='search-hl'>` 标签 | ✅ |
| IK 分词：`苹果手机` → `["苹果","手机"]` | ✅ |
| 搜索"手机"不误命中"机械键盘" | ✅ |
| 无 keyword 时返回全量分页（MySQL） | ✅ |
| README 性能对比表格（实测数据） | ✅ |

## 性能对比（实测）

| 方式 | 暖均值(2-5次) | P99(暖) |
|------|-------------|--------|
| MySQL LIKE | 47ms | 59ms |
| ES 搜索 | 53ms | 57ms |

> 5 条数据小数据集下两者持平；规模扩大后 ES 倒排索引优势显现。

---

## 遗留说明

1. **sync_fail_log 重试**：失败记录只写表，未实现定时重试补偿。
2. **多实例 Caffeine 缓存广播**：多实例部署时本地缓存无法同步失效。
3. **销量字段**：`sales` 当前固定为 0，下单成功后未回写 ES。
