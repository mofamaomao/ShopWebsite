# 验收报告 — 电商购物商城 Demo

日期：2026-05-30
开发周期：4 天（2026-05-27 ～ 2026-05-30）
验收人：项目负责人

---

## 阶段完成情况

| 阶段 | 描述 | 必须项 | 通过数 | 状态 |
|------|------|--------|--------|------|
| 阶段一 | 环境搭建（Spring Boot 脚手架 + Vue 3 脚手架 + MySQL/Redis 联通） | 1 | 1 | ✅ 完成 |
| 阶段二 | 后端 API（注册/登录/商品/购物车/订单 7 条接口） | 7 | 7 | ✅ 完成 |
| 阶段三 | 前端开发（登录注册/商品列表/商品详情/购物车/下单全流程） | 5 | 5 | ✅ 完成 |
| 阶段四 | 验收测试（TC-01 ～ TC-07 共 24 个断言全部通过） | 7 | 7 | ✅ 完成 |
| 购物车修复 | 库存校验、角标同步、数量编辑、商品删除 | 3 | 3 | ✅ 完成 |

### 7 条必须接口验收结果

| # | 接口 | HTTP 方法 | 认证 | 结果 |
|---|------|-----------|------|------|
| 1 | `/api/auth/register` | POST | 无 | ✅ 通过 |
| 2 | `/api/auth/login` | POST | 无 | ✅ 通过 |
| 3 | `/api/products` | GET | 无 | ✅ 通过 |
| 4 | `/api/products/{id}` | GET | 无 | ✅ 通过 |
| 5 | `/api/cart` | POST | JWT | ✅ 通过 |
| 6 | `/api/cart` | GET | JWT | ✅ 通过 |
| 7 | `/api/orders` | POST | JWT | ✅ 通过 |

### 5 条端到端用例验收结果

| # | 用例描述 | 结果 |
|---|----------|------|
| E2E-01 | 用户注册 → 登录 → 获取 JWT → 访问受保护接口 | ✅ 通过 |
| E2E-02 | 关键词搜索商品 → 分页翻页 → 查看详情 | ✅ 通过 |
| E2E-03 | 多次加购同一商品 → 购物车角标数量正确累加 | ✅ 通过 |
| E2E-04 | 购物车结算 → 下单 → 库存扣减 → 跳转订单成功页 | ✅ 通过 |
| E2E-05 | 库存不足场景 → 下单被后端拒绝 → 前端展示错误提示 | ✅ 通过 |

---

## 遇到的问题与解决方案

### 问题 1：Java 版本不匹配（class file version 65 vs 61）

**现象**：本地运行 `mvn spring-boot:run` 报 `UnsupportedClassVersionError`，class file version 65 对应 Java 21，本地只有 Java 17（version 61）。

**原因**：初始生成的 `pom.xml` 将 `java.version` 设置为 21，与本地 JDK 17 不兼容。

**解决**：将 `pom.xml` 中 `<java.version>21</java.version>` 改为 `<java.version>17</java.version>`，重新编译通过。

---

### 问题 2：MySQL 密码被环境变量覆盖

**现象**：后端启动后连接 MySQL 报 `Access denied for user 'root'@'localhost'`。

**原因**：系统存在环境变量 `DB_PASSWORD=root`，Spring Boot 自动将其注入，覆盖了 `application.yml` 中配置的 `password: redhat`。

**解决**：在 `application.yml` 中将密码改为硬编码字面量（不使用 `${DB_PASSWORD:redhat}` 占位符），使其不受环境变量干扰。

---

### 问题 3：前端跨域请求被 CORS 拦截

**现象**：前端页面发起 API 请求，浏览器报 `CORS policy: No 'Access-Control-Allow-Origin' header`。

**原因**：Vite 默认开发端口 5173 被 Windows 防火墙拦截，导致实际访问端口变为 6589，而后端 CORS 配置仍为 `http://localhost:5173`。

**解决**：将 `application.yml` 中 `cors.allowed-origin` 更新为 `http://localhost:6589`，并统一在启动命令中使用 `--port 6589`。

---

### 问题 4：商品接口返回 401 Unauthorized

**现象**：未登录用户访问 `/api/products` 返回 401，商品列表页空白。

**原因**：`SecurityConfig` 的 `permitAll` 规则只放行了 `/api/auth/**`，遗漏了 `/api/products` 和 `/api/products/**`。

**解决**：在 `SecurityConfig.java` 的 `requestMatchers` 中补充 `/api/products`、`/api/products/**`，使商品接口无需登录即可访问。

---

### 问题 5：购物车角标数量重复累加

**现象**：多次点击"加入购物车"后，导航栏角标数字持续累加，远超实际购物车数量。

**原因**：`cart.js` store 的 `addItem` 方法使用 `cartCount.value += qty` 本地叠加，与服务端实际状态脱节；若接口报错也仍会累加。

**解决**：将 `addItem` 改为 `await addToCartApi(...)` 后调用 `await fetchCount()`，每次操作后从服务端重新拉取真实总数。

---

## 未完成的可选项

| 可选功能 | 原因 |
|----------|------|
| 商品图片上传 | 需要配置 OSS（如阿里云 OSS）或本地文件服务，超出 Demo 范围 |
| 用户个人资料编辑（昵称/密码修改） | 非核心购物链路，时间有限暂未实现 |
| 订单状态流转（支付/取消） | 真实支付需对接第三方，Demo 仅保留 PENDING 状态 |
| 购物车数据持久化（跨 Redis 重启保留） | 当前纯 Redis 存储，Redis 重启后购物车清空 |

---

## 后续优化建议

1. **购物车持久化双写**：在 Redis Hash 的基础上，同步写入 MySQL `cart` 表，启动时从 MySQL 恢复，防止 Redis 重启导致数据丢失。

2. **订单创建异步化**：引入消息队列（RocketMQ / Kafka），将库存扣减和订单落库从同步接口解耦到消费端，支撑秒杀等高并发场景。

3. **接口幂等性保护**：下单接口增加客户端防重 Token，服务端用 Redis SETNX 校验，防止网络抖动导致重复提交订单。

4. **商品全文搜索引擎化**：当前使用 MySQL `LIKE '%keyword%'` 查询，无法走索引。建议引入 Elasticsearch，支持中文分词、相关度排序和高亮显示。

5. **前端接口缓存与离线体验**：对商品列表、详情页添加 HTTP 缓存头（ETag / Cache-Control），减少重复请求；购物车在网络异常时提示用户而非静默失败。
