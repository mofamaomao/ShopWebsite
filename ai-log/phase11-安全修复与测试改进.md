# Phase 11 — 安全修复：403/401 区分 + 测试数据污染 + 中文编码乱码

## 修复背景

验收测试中发现三个独立问题：
1. **T1-5**：普通用户访问 `/api/admin/**` 应返回 403，实际返回 401
2. **T4-13**：PowerShell 管理员测试脚本多次运行后，遗留 `PSTestProduct` 残留数据
3. **管理后台乱码**：分类、品牌、昵称显示 `鑻规灉`、`鎵嬫満鏁板瓧` 等乱码

---

## 问题一：403 vs 401 混淆

### 根本原因

`SecurityConfig` 中 `accessDeniedHandler` 原先使用 `res.sendError(403, ...)` ：

```java
// 错误写法
res.sendError(HttpServletResponse.SC_FORBIDDEN, "Forbidden");
```

`sendError()` 会触发 Servlet 的错误转发机制，Spring Boot 将请求重新分发到 `/error` 端点，
该端点检测到没有有效认证后，再次触发 `authenticationEntryPoint`，最终吐出 401。

### 修复

改为直接写响应体，绕过错误转发管道：

```java
.authenticationEntryPoint((req, res, e) -> {
    res.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
    res.setContentType(MediaType.APPLICATION_JSON_VALUE);
    res.getWriter().write("{\"code\":401,\"msg\":\"Unauthorized\",\"data\":null}");
})
.accessDeniedHandler((req, res, e) -> {
    res.setStatus(HttpServletResponse.SC_FORBIDDEN);
    res.setContentType(MediaType.APPLICATION_JSON_VALUE);
    res.getWriter().write("{\"code\":403,\"msg\":\"Forbidden\",\"data\":null}");
})
```

同时移除了不再使用的 `@EnableMethodSecurity` 注解。

---

## 问题二：测试数据污染

### 根本原因

PowerShell 脚本硬编码商品名 `"PSTestProduct"`，多次运行后遗留重名记录。

### 修复

改为时间戳唯一名：

```powershell
$PROD_NAME = "PSTest_$(Get-Date -Format 'yyyyMMddHHmmss')"
```

---

## 问题三：中文字符乱码

### 根本原因

`migration_admin.sql` 在 Windows 中文环境下用 MySQL 客户端执行，
客户端字符集为 GBK，将 UTF-8 文件中的中文字节当作 GBK 解码后存入数据库。

验证：`'苹果'.encode('utf-8').decode('gbk')` → `'鑻规灉'`，与截图完全吻合。

### 修复

新建 `docs/fix_encoding.sql`，用十六进制字面量写入，彻底绕过客户端字符集：

```sql
-- 执行: mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/fix_encoding.sql
UPDATE `category` SET `name` = x'E6898BE69CBAE695B0E7A081' WHERE id = 1; -- 手机数码
UPDATE `brand`    SET `name` = x'E88BB9E69E9C'             WHERE id = 1; -- 苹果
UPDATE `user` SET `nickname` = x'E7AEA1E79086E59198'       WHERE id = 1000; -- 管理员
```

昵称乱码在修复 DB 后仍显示异常，原因是浏览器 `localStorage` 缓存了旧值；退出重新登录后恢复正常。

---

## 修改文件

| 文件 | 改动 |
|---|---|
| `config/SecurityConfig.java` | `sendError` → `setStatus` + 直接写 JSON；移除 `@EnableMethodSecurity` |
| `docs/test_admin.ps1` | 商品名改为时间戳唯一名 |
| `docs/fix_encoding.sql` | 新建：hex 字面量修复乱码数据 |

---

## 验收结果

| 场景 | 修复前 | 修复后 |
|---|---|---|
| USER token 访问 /api/admin/** | 401 | **403** ✅ |
| 重复运行测试脚本 | 残留数据 | 每次唯一，无污染 ✅ |
| 管理后台分类/品牌 | 乱码 | 正常中文 ✅ |
