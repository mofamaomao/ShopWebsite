# Phase 6 归档 — Elasticsearch 全文搜索集成

**日期：** 2026-06-02
**分支：** claude/jolly-edison-MpzBv

---

## 目标

在已有电商 Demo 基础上完成 Elasticsearch 集成（E1）：

- **E1-Step2**：设计 `product` 索引 Mapping，支持 IK 中文分词（本地回退为 standard）。
- **E1-Step3**：Spring Data ES 集成，`ProductDocument` 实体映射。
- **E1-Step4a**：`POST /api/admin/es/init` 批量将 MySQL 商品同步至 ES。
- **E1-Step4b**：ProductService 写操作双写 ES，失败只记日志和 `sync_fail_log`，不影响主流程。

---

## Prompt 原文

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

---

## AI 输出摘要

### 新增文件

1. **`resources/es/product-mapping.json`**：索引 Mapping，包含 settings（IK 分析器定义）+ mappings（7个字段）。本地测试版使用 `standard` 分析器（IK 插件不可用时回退）。

2. **`common/EsConstants.java`**：`PRODUCT_INDEX = "product"` 常量，全局唯一索引名来源。

3. **`common/EsConverter.java`**：`toDocument(Product)` 静态工具，`price` 用 `BigDecimal.doubleValue()` 转换，`createdAt` 填入当前毫秒时间戳。

4. **`entity/ProductDocument.java`**：`@Document(indexName = EsConstants.PRODUCT_INDEX, createIndex = false)`，`price = Double`，`createdAt = Long + @Field(type=Long)`。

5. **`repository/ProductSearchRepository.java`**：`ElasticsearchRepository<ProductDocument, Long>`，独立 `repository` 包（避开 `@MapperScan`）。

6. **`entity/SyncFailLog.java` + `mapper/SyncFailLogMapper.java`**：双写失败审计表，`@Insert` 注解写入。

7. **`service/ProductSearchService.java` / `impl/ProductSearchServiceImpl.java`**：
   - `bulkInit(List<Product>)`：批量 `saveAll`
   - `syncSave(Product)`：单条 upsert，异常 → log ERROR + `writeFailLog`
   - `syncDelete(Long)`：按 ID 删除，异常 → log ERROR + `writeFailLog`
   - `writeFailLog` 内部再套 try-catch，保证绝不向上抛

8. **`controller/EsAdminController.java`**：`POST /api/admin/es/init`，调用 `productMapper.findAll()` + `productSearchService.bulkInit()`，返回同步条数。

9. **`config/RedissonConfig.java`**：手动创建 `RedissonClient` Bean，密码为空时跳过 `setPassword()`，覆盖自动配置。

10. **`docs/migration_es.sql`**：`CREATE TABLE IF NOT EXISTS sync_fail_log`（id / product_id / operation / error_msg / created_at）。

### 修改文件

- **`pom.xml`**：新增 `spring-boot-starter-data-elasticsearch`，保留 Redisson + Caffeine。
- **`application.yml`**：新增 `spring.elasticsearch.uris`（默认 `http://localhost:9200`）。
- **`service/ProductService.java`**：新增 `createProduct / updateProduct / deleteProduct` 接口方法。
- **`service/impl/ProductServiceImpl.java`**：写方法调用 `productSearchService.syncSave/syncDelete` 实现双写。
- **`config/SecurityConfig.java`**：`/api/admin/es/init` 加入 permitAll。

---

## 报错解决记录

| # | 报错关键信息 | 原因 | 解决方案 |
|---|------------|------|----------|
| 1 | `ConflictingBeanDefinitionException: productSearchRepository` | `ProductSearchRepository` 放在 `com.shop.mapper` 包，`@MapperScan("com.shop.mapper")` 把它当 MyBatis Mapper 注册，与 Spring Data ES 工厂 Bean 冲突 | 移至新包 `com.shop.repository`，脱离 `@MapperScan` 扫描范围 |
| 2 | `RedisConnectionException: ERR AUTH called without any password configured` | `spring.data.redis.password` 默认为空字符串 `""`，Redisson 自动配置仍发送 `AUTH ""`，本地 Redis 无密码拒绝 | 新增 `RedissonConfig` 手动创建 `RedissonClient`，密码为空时不调用 `setPassword()`，覆盖自动配置 |
| 3 | `mapper_parsing_exception: analyzer [ik_smart] has not been configured` | IK 插件未安装，Spring Data ES 启动时尝试自动建索引，Mapping 中引用了 `ik_smart`/`ik_max_word` 但 ES 不认识 | 加 `createIndex = false` 禁止自动建索引；本地测试将分析器改为内置 `standard` |
| 4 | `WARN: Unsupported type 'class java.lang.Long' for date property 'createdAt'` | `createdAt` 声明为 `@Field(type = FieldType.Date)` 但 Java 类型是 `Long`，类型不匹配 | 改为 `@Field(type = FieldType.Long)`，mapping JSON 中对应字段改为 `"type": "long"` |
| 5 | IK 插件下载 404 / `FileNotFoundException` | `infinilabs/analysis-ik` 对应 ES 8.13.0 的 zip 包 URL 不存在 | 本地测试使用 `standard` 分析器替代；生产环境需手动下载对应版本 zip 后 `docker cp` 安装 |

---

## 变更文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `shop-backend/pom.xml` | 修改 | 新增 spring-boot-starter-data-elasticsearch |
| `resources/application.yml` | 修改 | 新增 spring.elasticsearch.uris |
| `resources/es/product-mapping.json` | 新增 | 索引 Mapping（standard 分析器，本地可用） |
| `common/EsConstants.java` | 新增 | 索引名常量 PRODUCT_INDEX |
| `common/EsConverter.java` | 新增 | Product → ProductDocument 转换工具 |
| `entity/ProductDocument.java` | 新增 | ES 文档实体，createIndex=false |
| `entity/SyncFailLog.java` | 新增 | 双写失败审计实体 |
| `repository/ProductSearchRepository.java` | 新增 | ElasticsearchRepository（独立包） |
| `mapper/SyncFailLogMapper.java` | 新增 | 失败日志写入 Mapper |
| `service/ProductSearchService.java` | 新增 | bulkInit / syncSave / syncDelete 接口 |
| `service/impl/ProductSearchServiceImpl.java` | 新增 | ES 操作实现，失败只记录不抛出 |
| `controller/EsAdminController.java` | 新增 | POST /api/admin/es/init |
| `config/RedissonConfig.java` | 新增 | 自定义 RedissonClient，空密码不发 AUTH |
| `service/ProductService.java` | 修改 | 新增 createProduct/updateProduct/deleteProduct |
| `service/impl/ProductServiceImpl.java` | 修改 | 写方法追加 ES 双写调用 |
| `config/SecurityConfig.java` | 修改 | /api/admin/es/init 加入 permitAll |
| `docs/migration_es.sql` | 新增 | CREATE TABLE sync_fail_log |

---

## 验收结果

| 验收项 | 结果 |
|--------|------|
| `PUT /product` 建索引返回 `acknowledged: true` | ✅ |
| `POST /api/admin/es/init` 返回 `{"code":200,"data":5}` | ✅ |
| `GET /product/_count` 返回 `{"count":5}` | ✅ |
| `_search` 返回完整文档（name/price/stock/sales/createdAt） | ✅ |
| 双写失败不影响主流程，写 sync_fail_log | ✅（设计验证） |
| 后端正常启动，无 Bean 冲突 | ✅ |

---

## 遗留与说明

1. **IK 分析器**：生产环境需安装 `analysis-ik` 插件并换回 `ik_max_word`/`ik_smart` 分析器；本地 Demo 使用 `standard` 分析器功能可用但中文分词效果较差（按字符切分）。
2. **搜索接口**：本阶段只实现了数据写入和同步，`GET /api/products/search?q=xxx` 搜索接口尚未开发。
3. **sync_fail_log 重试**：失败记录目前只写表，未实现定时重试补偿，后续可加调度任务扫表重跑。
