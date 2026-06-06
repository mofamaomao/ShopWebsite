# Phase 12 — 支付宝沙箱 PC 网页支付集成

## 目标

用支付宝沙箱 SDK 替换原有模拟支付，实现完整的 PC 端收银台支付流程：
- 下单后跳转支付宝收银台（真实 HTML 表单，新窗口打开）
- 前端 3 秒轮询 `/api/pay/query/{orderId}` 检测支付结果
- 异步回调 `/api/pay/notify` **必须验签**（安全红线）
- 支付金额以服务端订单金额为准，不信任前端传参
- 私钥/公钥全部走环境变量，不入库不入代码

---

## 架构

```
前端 OrderPayView
  └── 点击"立即支付" → POST /api/pay/create
                              ↓
                        PayController
                              ↓
                        PayService.createPayForm()
                              ↓ AlipayTradePagePayRequest
                        支付宝沙箱 API
                              ↓ HTML Form (body)
                        前端 window.open() 新窗口渲染表单
                              ↓ 用户完成支付
              ┌─────────────────────────────────┐
              │                                 │
        同步跳转 return-url              异步回调 notify-url
    /order-success?out_trade_no=...   POST /api/pay/notify
              │                             ↓
        展示成功页                    验签（RSA2）
                                           ↓
                                    更新订单 → PAID
                                    （幂等：已PAID则跳过）

前端同时每 3s 轮询 GET /api/pay/query/{orderId}
  → PayService.queryPayStatus() → 支付宝交易查询 API
  → TRADE_SUCCESS 时跳转成功页
```

---

## 安全约束（不可妥协）

| 约束 | 实现 |
|---|---|
| 私钥不入代码/git | 全部走环境变量 `ALIPAY_PRIVATE_KEY` 等，`.env` 已加入 `.gitignore` |
| notify 必须验签 | `AlipaySignature.rsaCheckV1()` 验签失败直接 `return false`，不处理 |
| 金额以服务端为准 | `createPayForm()` 从 `OrderMapper.findByOrderNo()` 查实际金额，不接受前端传入 |
| 幂等处理 | 检查 `order.status == PAID` 后跳过，防止重复回调重复更新 |

---

## 新增 / 修改文件

### 后端新增

| 文件 | 说明 |
|---|---|
| `config/AlipayConfig.java` | 读取 4 个支付宝配置项；appId 为空时返回 null bean 并打印 WARN，跳过初始化 |
| `common/PayException.java` | 支付专用异常，携带 HTTP code，全局异常处理器捕获 |
| `service/PayService.java` | 接口：createPayForm / queryPayStatus / handleNotify |
| `service/impl/PayServiceImpl.java` | 实现：SDK 调用 + 验签 + 幂等更新订单状态 |
| `controller/PayController.java` | 4 个端点（见下） |

### 后端修改

| 文件 | 改动 |
|---|---|
| `pom.xml` | 新增 `alipay-sdk-java 4.38.10.ALL` 依赖 |
| `application.yml` | 新增 alipay.* 配置块，占位符均带空默认值 `${VAR:}` |
| `SecurityConfig.java` | `/api/pay/notify`、`/api/pay/return` 加入 `permitAll()` |
| `GlobalExceptionHandler.java` | 新增 `PayException` handler |

### 前端修改

| 文件 | 改动 |
|---|---|
| `api/order.js` | 新增 `createPay`、`queryPayStatus` 两个 API 方法 |
| `views/OrderPayView.vue` | 重构：新窗口渲染支付宝表单 + 3 秒轮询 |
| `views/OrderSuccessView.vue` | 兼容两种参数来源：Vue 路由跳转（orderId/totalPrice）和支付宝 sync return（out_trade_no/total_amount） |

---

## API 端点

| 方法 | 路径 | 认证 | 说明 |
|---|---|---|---|
| POST | `/api/pay/create` | JWT | 生成支付宝收银台 HTML 表单 |
| GET | `/api/pay/query/{orderId}` | JWT | 查询支付状态（轮询用） |
| POST | `/api/pay/notify` | 无（支付宝回调） | 异步回调：验签 + 更新订单 |
| GET | `/api/pay/return` | 无 | 同步跳转（仅重定向，不处理业务） |

---

## 启动配置要点

Spring Boot 不自动加载 `.env` 文件。推荐在 `shop-backend/` 目录下创建 `config/application.yml`（Spring Boot 优先加载工作目录下的 config/）：

```yaml
# shop-backend/config/application.yml（不提交到 git）
alipay:
  app-id: 9021000164646155
  private-key: MIIEvw...（一行，无换行）
  public-key:  MIIBIj...（一行，无换行）
  notify-url:  https://xxxx.ngrok-free.dev/api/pay/notify
  return-url:  http://localhost:6589/order-success
```

在 `.gitignore` 中追加 `config/` 防止密钥入库。

---

## 调试过程记录（踩坑）

| 问题 | 原因 | 解决 |
|---|---|---|
| 启动报 `Could not resolve placeholder 'ALIPAY_APP_ID'` | yml 占位符无默认值 | 改为 `${ALIPAY_APP_ID:}` 空默认 |
| AlipayClient Bean 不创建（无日志） | `@ConditionalOnExpression` 在 Spring Boot 3 对 `.isEmpty()` 解析异常 | 改为 `@Bean` 方法内 `if (appId.isEmpty()) return null` |
| `-Dalipay.app-id=xxx` 不生效 | PowerShell 调用 Maven 批处理时系统属性传递不稳定 | 改用 `shop-backend/config/application.yml` 覆盖 |
| 成功页显示 `订单号：undefined` | 支付宝 sync return 带 `out_trade_no`，非 `orderId` | OrderSuccessView 兼容两套参数名 |
| CORS 403 | 前端跑在 5173，后端只允许 6589 | 改用 `npm run dev -- --port 6589` |
| MySQL 密码 `redhat` 拒绝 | 本机 root 密码不是 `redhat` | yml 改为 `${DB_PASSWORD:redhat}`，支持环境变量覆盖 |

---

## 验收结果

| 用例 | 状态 |
|---|---|
| 下单 → 支付宝收银台新窗口打开 | ✅ |
| 沙箱买家账号完成支付 | ✅ |
| 支付成功后跳转成功页，显示订单号和金额 | ✅ |
| 后端日志出现 `支付回调验签成功` | ✅ |
| 未配置支付宝时服务正常启动，点支付返回明确错误 | ✅ |
| 私钥不出现在任何 git 提交中 | ✅ |
