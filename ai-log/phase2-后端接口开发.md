# Phase 2 归档 — 后端接口开发

## 目标
实现 7 个后端 API，完成完整的电商核心流程。

## 技术栈
- Spring Boot 3.3.5 / Java 17
- MyBatis + XML Mapper + PageHelper
- Spring Security 无状态 JWT（jjwt 0.12.3）
- Redis（Docker）存购物车
- MySQL 8（本地）
- springdoc-openapi 2.3.0（Swagger UI）

---

## 实现的接口

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| POST | /api/auth/register | 注册，BCrypt 加密密码 | 无 |
| POST | /api/auth/login | 登录，返回 JWT token | 无 |
| GET  | /api/products | 商品列表（PageHelper 分页） | 无 |
| GET  | /api/products/{id} | 商品详情 | 无 |
| POST | /api/cart | 加入购物车（Redis HINCRBY 幂等） | 需登录 |
| GET  | /api/cart | 查看购物车（联查商品信息） | 需登录 |
| POST | /api/orders | 创建订单（SELECT FOR UPDATE 库存校验） | 需登录 |

---

## 关键设计

### 统一响应体
```java
Result<T> { int code; String msg; T data; }
```
成功返回 `code:200`，业务异常通过 `BusinessException` + `GlobalExceptionHandler` 统一处理。

### JWT 认证流程
1. 登录成功 → `JwtUtils.generateToken(userId)` 生成 token
2. 请求携带 `Authorization: Bearer <token>`
3. `JwtAuthFilter` 解析 token，将 `userId` 设为 `Authentication.principal`
4. Controller 通过 `authentication.getPrincipal()` 取 userId

### 购物车（Redis Hash）
- Key：`cart:{userId}`
- Field：`productId`，Value：累计数量
- `HINCRBY` 保证重复加购叠加而非覆盖

### 订单库存校验
```sql
SELECT * FROM product WHERE id = #{id} FOR UPDATE
```
在 `@Transactional` 事务内 SELECT FOR UPDATE 锁行，校验库存后原子扣减。

---

## 验证结果（2026-05-28）

```
POST /api/auth/register  → 200  {"code":200,"data":2}
POST /api/auth/login     → 200  {"code":200,"data":{"token":"eyJ..."}}
GET  /api/products       → 200  {"code":200,"data":{"total":5,"list":[...]}}
GET  /api/products/1     → 200  {"code":200,"data":{"id":1,"name":"iPhone 15 Pro",...}}
POST /api/cart           → 200  {"code":200,"data":null}
GET  /api/cart           → 200  {"code":200,"data":{"items":[{"productName":"iPhone 15 Pro","quantity":2,"subtotal":19998.00}],"total":19998.00}}
POST /api/orders         → 200  {"code":200,"data":{"orderId":2,"totalPrice":9999.00,"status":"PENDING"}}
```

---

## 遇到的问题与解决

| 问题 | 原因 | 解决方式 |
|------|------|----------|
| UnsupportedClassVersionError | 云端 Java 21 编译，本地 Java 17 运行 | pom.xml 改 `<java.version>17</java.version>` |
| 500 Access denied for root@localhost | `DB_PASSWORD=root` 环境变量覆盖了 yml 默认值 | application.yml 硬编码 `password: redhat` |
| user 表查询报错 | `user` 是 MySQL 保留字 | UserMapper.xml 所有 SQL 改用反引号 `` `user` `` |
| /api/products 返回 401 | SecurityConfig 白名单漏了商品接口 | 添加 `/api/products`, `/api/products/**` |
| 前端 CORS 失败 | 前端被迫跑在 6589 端口，CORS 只允许 5173 | application.yml 改为 `allowed-origin: http://localhost:6589` |
| 购物车 401 | Redis Docker 未启动 | `docker run -d -p 6379:6379 redis` |
| 登录一直 500 | 本地有两个 MySQL 服务，启动了错误的那个 | 切换到正确的 MySQL 服务 |

---

## 本地环境说明
- MySQL：本地两个服务，使用正确的那个，密码 `redhat`
- Redis：Docker 容器 `redis:latest`，端口 6379
- 前端端口：6589（5173 被 Windows 占用）
- 后端端口：8080
