# 阶段一归档 — 环境搭建

**日期：** 2026-05-27
**分支：** claude/jolly-edison-MpzBv

---

## 目标

前后端分离电商 Demo 项目的环境初始化，包含后端 Spring Boot 脚手架、数据库建表、前端 Vue 3 脚手架，以及两端的基础配置联调。

---

## Prompt 原文

```
你是一名全栈工程师，正在搭建一个电商 Demo 项目（前后端分离）。

# Task — 阶段一：环境搭建
请按以下步骤完成项目初始化：

## 后端（Spring Boot）
1. 使用 Spring Initializr 创建项目，依赖选择：
   Spring Web / MyBatis / MySQL Driver / Lombok / Spring Security / Validation
2. 在 application.yml 配置数据库连接（localhost:3306/shop_demo）
3. 创建以下三张表，并写好对应的 Entity / Mapper：
   - user(id, phone, password, nickname, created_at)
   - product(id, name, price, stock, category, image_url, description)
   - order(id, user_id, total_price, status, created_at)
4. 全局配置 CORS：允许 http://localhost:5173
5. 写一个 /api/health GET 接口返回 "ok"，验证启动正常

## 前端（Vue 3 + Vite）
1. 执行: npm create vite@latest shop-frontend -- --template vue
2. 安装依赖: npm install axios vue-router pinia element-plus
3. 在 vite.config.js 配置 proxy：/api → http://localhost:8080
4. 创建目录结构：src/api / src/views / src/stores / src/router / src/components
5. 创建 src/api/http.js：配置 Axios baseURL、请求/响应拦截器（自动带 token，401 跳转登录）

## 约束
- 代码必须通过编译，不允许留 TODO 占位未实现的关键逻辑
- 所有配置项不要硬编码，放入 .env 文件
- 不要引入 Redis、Elasticsearch（本阶段暂不需要）
```

---

## AI 输出摘要

1. **后端项目结构**：创建 Spring Boot 3.3.5 + Java 17 项目，pom.xml 包含 Web / MyBatis / MySQL / Lombok / Security / Validation / H2(test) 依赖。

2. **数据库配置**：application.yml 所有连接参数读自环境变量（含默认值），shop-backend/.env 存放本地开发配置，schema.sql 提供三张表完整 DDL，含外键约束（order.user_id → user.id）。

3. **Entity + Mapper**：User / Product / Order 三个 Lombok @Data 实体类，对应三个 MyBatis XML Mapper，实现 findById / findAll / insert / update / deleteById 基础 CRUD。

4. **CORS 配置**：CorsConfig 通过 CorsFilter Bean 全局允许 http://localhost:5173，支持携带 Cookie（allowCredentials=true）。

5. **Security 配置**：SecurityConfig 关闭 CSRF，Stateless 会话，/api/health 和 /api/auth/** 公开，其余接口需认证；配置 AuthenticationEntryPoint 确保未认证请求返回 401（而非默认 403）。

6. **健康检查接口**：HealthController GET /api/health → 返回字符串 "ok"。

7. **前端脚手架**：npm create vite 生成 Vue 3 项目，安装 axios / vue-router / pinia / element-plus，vite.config.js 配置 /api 代理到 8080、@/ 路径别名。

8. **Axios 封装**：src/api/http.js 设置 baseURL=/api、timeout=10000，请求拦截器自动附加 Bearer token，响应拦截器统一处理 401 跳转 /login。

9. **页面骨架**：LoginView（手机号+密码表单含校验）、HomeView（调用 /api/health 显示连接状态）、路由守卫（无 token 强制跳转登录）、Pinia useUserStore（token 持久化到 localStorage）。

---

## 验收结果

| 验收项 | 结果 |
|--------|------|
| `mvn clean spring-boot:run` 无报错，端口 8080 可访问 | ✅ |
| `GET /api/health` 返回 `ok` | ✅ |
| CORS 预检返回 `Access-Control-Allow-Origin: http://localhost:5173` | ✅ |
| 未携带 token 访问受保护接口返回 `401` | ✅ |
| `npm install && npm run dev` 后 localhost:5173 可访问 | ✅ |
| `npm run build` 构建成功（1.09s） | ✅ |
| 数据库三张表建立，含测试种子数据 | ✅ |
| 代码推送至 GitHub 分支 claude/jolly-edison-MpzBv | ✅ |

---

## 遗留问题

1. **GitHub App 写权限未配置**：云端环境的 git push 需要通过 PAT 完成，正式项目建议配置 GitHub App 或 Deploy Key。
2. **测试类暂用 H2**：ShopApplicationTests 用 H2 内存库跳过 MySQL 依赖，后续集成测试需切换为 Testcontainers。
3. **JWT 未实现**：SecurityConfig 已预留 stateless 架构，但 token 解析过滤器留待阶段二完成。
4. **前端 /api/auth/login 尚未联通**：LoginView 的提交逻辑已写，但后端登录接口是阶段二任务。
5. **Windows 换行符**：本机 Windows 环境下 curl 多行命令需写成单行，项目文档已更正。

---

## 截图

> 请将以下截图放入 ai-log/screenshots/phase1/ 目录：
> - [ ] `mvn spring-boot:run` 启动成功日志
> - [ ] `curl http://localhost:8080/api/health` 返回 ok
> - [ ] CORS 预检响应头（Access-Control-Allow-Origin）
> - [ ] `curl .../api/user/me` 返回 401
> - [ ] localhost:5173 首页截图
> - [ ] MySQL SHOW TABLES 结果
