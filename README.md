# ShopWebsite — 电商购物商城 Demo

一个基于 Spring Boot + Vue 3 的前后端分离电商演示项目，实现了用户注册/登录、商品列表、购物车（Redis）和下单（防超卖）全链路流程。

---

## 技术栈

| 层次 | 技术 | 版本 |
|------|------|------|
| **前端框架** | Vue | 3.5.34 |
| **前端路由** | Vue Router | 5.0.7 |
| **状态管理** | Pinia | 3.0.4 |
| **UI 组件库** | Element Plus | 2.14.0 |
| **HTTP 客户端** | Axios | 1.16.1 |
| **前端构建** | Vite | 8.0.12 |
| **后端框架** | Spring Boot | 3.3.5 |
| **Java 版本** | Java | 17 |
| **持久层** | MyBatis | 3.0.3 |
| **分页插件** | PageHelper | 2.1.0 |
| **JWT** | jjwt | 0.12.3 |
| **接口文档** | springdoc-openapi | 2.3.0 |
| **数据库** | MySQL | 8.x |
| **缓存/购物车** | Redis | 7.x |

---

## 本地启动步骤

### 前置条件

- Java 17（确保 `java -version` 输出 17.x）
- Maven 3.8+
- Node.js 18+
- MySQL 8.x（服务已启动，账号 root / 密码 redhat）
- Redis 7.x

### 1. 启动 Redis

```bash
docker run -d --name redis -p 6379:6379 redis:7
```

如果容器已存在：

```bash
docker start redis
```

### 2. 初始化数据库

```bash
mysql -u root -predhat < docs/schema.sql
mysql -u root -predhat shop_demo < docs/seed.sql
```

### 3. 启动后端

```bash
cd shop-backend
mvn spring-boot:run
```

后端默认监听 `http://localhost:8080`，启动完成后控制台输出 `Started ShopApplication`。

### 4. 启动前端

```bash
cd shop-frontend
npm install
npm run dev -- --port 6589
```

> 后端 CORS 已配置为 `http://localhost:6589`。如需使用其他端口，同步修改
> `shop-backend/src/main/resources/application.yml` 中的 `cors.allowed-origin`。

前端访问地址：**http://localhost:6589**

---

## 数据库初始化

| 文件 | 说明 |
|------|------|
| `docs/schema.sql` | 建表语句，含 `DROP TABLE IF EXISTS`，可幂等执行 |
| `docs/seed.sql` | 12 条商品测试数据，覆盖手机、电脑、耳机、外设、平板、配件 6 个分类 |

---

## 接口文档

后端启动后访问：

- **Swagger UI**：http://localhost:8080/swagger-ui.html
- **OpenAPI JSON**：http://localhost:8080/v3/api-docs

接口均按模块分组（`购物车（需登录）`、`订单（需登录）`、`商品`、`认证`），JWT 认证通过页面右上角 **Authorize** 按钮填入 `Bearer <token>`。

---

## 验收通过情况

### 7 条必须接口

| # | 接口 | 说明 | 状态 |
|---|------|------|------|
| 1 | `POST /api/auth/register` | 手机号注册 | ✅ 通过 |
| 2 | `POST /api/auth/login` | 登录返回 JWT | ✅ 通过 |
| 3 | `GET /api/products` | 商品列表（分页 + 关键词搜索） | ✅ 通过 |
| 4 | `GET /api/products/{id}` | 商品详情 | ✅ 通过 |
| 5 | `POST /api/cart` | 加入购物车（Redis HINCRBY 幂等） | ✅ 通过 |
| 6 | `GET /api/cart` | 查看购物车（联查商品，计算合计） | ✅ 通过 |
| 7 | `POST /api/orders` | 下单（SELECT FOR UPDATE 防超卖） | ✅ 通过 |

### 5 条端到端用例

| # | 用例 | 状态 |
|---|------|------|
| E2E-01 | 新用户注册 → 登录 → 获取 JWT → 访问受保护接口 | ✅ 通过 |
| E2E-02 | 商品关键词搜索 → 翻页 → 查看详情 | ✅ 通过 |
| E2E-03 | 多次加购同一商品 → 购物车数量正确累加（角标同步） | ✅ 通过 |
| E2E-04 | 购物车结算 → 下单 → 库存正确扣减 → 跳转成功页 | ✅ 通过 |
| E2E-05 | 库存不足场景下单 → 后端拒绝并返回错误信息 | ✅ 通过 |

---

## 支付宝沙箱配置（面试官复现指引）

### 前置：获取沙箱密钥

1. 登录 [支付宝开放平台](https://open.alipay.com) → **沙箱环境**
2. 记录 **沙箱 AppID**（形如 `2021000122XXXXXX`）
3. 在"沙箱应用 → 开发设置 → 接口加签方式"生成应用私钥（RSA2）并获取支付宝公钥

### 填写环境变量

编辑 `shop-backend/.env`（已加入 `.gitignore`，不会入库）：

```dotenv
ALIPAY_APP_ID=你的沙箱AppID
ALIPAY_PRIVATE_KEY=应用私钥(PKCS8格式，去掉-----BEGIN/END-----行及换行符)
ALIPAY_PUBLIC_KEY=支付宝公钥(去掉-----BEGIN/END-----行及换行符)
ALIPAY_NOTIFY_URL=https://xxxx.ngrok.io/api/pay/notify
ALIPAY_RETURN_URL=http://localhost:5173/order-success
```

### 内网穿透（异步通知必须）

```bash
ngrok http 8080
# 将输出的 https://xxxx.ngrok.io 填入 ALIPAY_NOTIFY_URL
```

### 沙箱买家账号

| 项目 | 值 |
|------|-----|
| 买家账号/密码 | 在开放平台沙箱控制台「沙箱账号」页面查看 |
| 支付密码 | 通常为 `111111` |

### 测试流程

1. 下单 → 跳转支付页 → 点击"立即支付（支付宝）"
2. 新窗口打开收银台，用沙箱买家账号完成支付
3. 原页面每 3 秒轮询 `/api/pay/query/{orderId}`，支付成功后自动跳转
4. 后端日志输出：`支付回调验签成功`

> **离线演示**：无 ngrok 时，支付成功后手动调用 `GET /api/pay/query/{orderId}` 可触发状态同步。

---

## ES 全文搜索性能对比

> 数据来自本地实测（Windows PowerShell，5 次，排除第 1 次冷启动均值）。
> 测试环境：5 条商品数据，ES 8.13.0 + standard 分析器，MySQL 8。

| 方式 | 暖均值(2-5次) | P99(暖) | 备注 |
|------|-------------|--------|------|
| MySQL LIKE | 47ms | 59ms | 含连接池命中 |
| ES 搜索 | 53ms | 57ms | 含 HTTP 往返 |

> **结论**：小数据集下两者持平。规模扩大后 ES 的全文分词和相关性排序优势会显现；当前 standard 分析器按字切词（`手机`→`手`+`机`），安装 IK 后中文搜索准确率将大幅提升。
