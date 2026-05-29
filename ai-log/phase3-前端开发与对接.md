# Phase 3 归档 — Vue 前端开发与对接

## 目标
基于已就绪的 7 个后端接口，完成完整的 Vue 3 前端页面开发与对接。

## 技术栈
- Vue 3 Composition API（script setup）
- Pinia 状态管理
- Vue Router 4（路由守卫）
- Element Plus 组件库
- Axios（封装在 src/api/）

---

## 新增 / 修改的文件

### API 模块（src/api/）
| 文件 | 说明 |
|------|------|
| http.js | 响应拦截器改为直接返回 res.data，业务错误 reject |
| auth.js | login / register |
| product.js | getProducts(page,size,keyword) / getProduct(id) |
| cart.js | getCart / addToCart |
| order.js | createOrder |

### Pinia Store（src/stores/）
| 文件 | 关键内容 |
|------|----------|
| user.js | token/nickname 持久化，isLoggedIn 计算属性，login()/register()/logout() |
| cart.js | cartCount 角标，fetchCount()/addItem() |

### 路由（src/router/index.js）
- 新增路由：/register、/product/:id、/cart、/order-success
- 守卫只保护 /cart 和 /order-success（requiresAuth meta）

### 页面（src/views/）
| 页面 | 核心功能 |
|------|----------|
| HomeView.vue | 商品网格，page/size/keyword 传后端，分页组件 |
| LoginView.vue | 表单校验，调用 store.login()，token 写 localStorage |
| RegisterView.vue | 注册表单，成功后跳登录页 |
| ProductView.vue | 商品详情，数量选择，加入购物车（未登录弹提示） |
| CartView.vue | 购物车列表，小计/合计，去结算调 /api/orders |
| OrderSuccessView.vue | 展示 orderId 和 totalPrice |

### 组件（src/components/）
- NavBar.vue：Logo + 搜索框（回车跳首页带 keyword 参数）+ 购物车角标 + 登录/退出

---

## 关键设计决策

### http.js 响应拦截器
```js
(response) => {
  const res = response.data          // { code, msg, data }
  if (res.code !== 200) return Promise.reject(new Error(res.msg))
  return res.data                    // 直接返回业务数据
}
```
所有 API 调用拿到的就是 data 字段，不需要每处再 .data。

### 搜索走后端
后端 ProductController 支持 keyword 模糊搜索，前端直接传参，不做客户端过滤。

### 购物车角标
登录后 NavBar.onMounted 调 fetchCount()；加购时 cartCount += qty 本地累加，无需额外请求。

---

## 测试结果（2026-05-29）

### API 自动化（test-phase3.ps1）
```
PASS 29   FAIL 0   total 29
```

### UI 手动验证
- 首页商品网格正常渲染
- 搜索 keyword 后端过滤，结果联动更新
- 商品详情页完整展示
- 未登录加购 -> 弹提示 -> 跳登录
- 登录/注册表单校验正常，token 写入 localStorage
- 登录后加购，导航栏角标更新
- 购物车列表、小计、合计正确
- 去结算 -> /order-success 显示订单号
- 退出后访问 /cart 自动跳 /login

---

## 遇到的问题与解决

| 问题 | 原因 | 解决 |
|------|------|------|
| PowerShell 脚本 & 报错 | PS 解析器把字符串里的 & 当运算符 | `$AMP = [char]38` 绕过 |
| PowerShell 中文乱码导致 ' 截断 | 文件 UTF-8 被 PS 按系统 ANSI 读 | 所有 label 改为纯 ASCII |
| `$pid` 只读 | PowerShell 内置进程 ID 变量 | 改名 `$prodId` |
| 分页不生效 | 后端参数名是 page/size，前端传 pageNum/pageSize | 对齐为 page/size |
| 搜索只过滤当页 | 前端做客户端过滤 | 改为传 keyword 给后端 |
