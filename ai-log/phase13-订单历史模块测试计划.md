# Phase 13 — 订单历史模块（U1）测试计划

## 被测范围

| 层 | 变更 |
|---|---|
| DB | `order` 新增 pay_time / cancel_time / remark；`order_item` 新增 product_name / product_img / subtotal |
| 后端 | GET /api/user/orders、GET /api/user/orders/{orderNo}、POST /api/user/orders/{orderNo}/cancel |
| 快照 | 下单时 MQ Consumer 将商品名/图/小计写入 order_item |
| 支付 | 支付成功后 pay_time 写入 |
| 前端 | /user/orders 页面：Tab 筛选 + 卡片 + 分页 + 详情弹窗 + PopConfirm 取消 |

---

## 自动化脚本

```bash
# PowerShell（需后端 + RabbitMQ 已启动）
.\docs\test_order_history.ps1
```

---

## 测试项详表

### T1 — 认证守卫

| ID | 操作 | 预期 |
|---|---|---|
| T1-1 | GET /api/user/orders（无 token） | HTTP 401 |
| T1-2 | GET /api/user/orders/{orderNo}（无 token） | HTTP 401 |
| T1-3 | POST /api/user/orders/{orderNo}/cancel（无 token） | HTTP 401 |

### T2 — 订单列表

| ID | 操作 | 预期 |
|---|---|---|
| T2-1 | GET /api/user/orders（有 token） | HTTP 200，data 含 list/total/page/size |
| T2-2 | 刚创建的订单出现在列表 | list 中 orderNo 匹配 |
| T2-3 | itemCount 字段 | >= 1 |
| T2-4 | ?status=PENDING_PAYMENT | 返回结果全为 PENDING_PAYMENT |
| T2-5 | ?status=PAID | 返回结果全为 PAID |
| T2-6 | ?status=CANCELLED | 返回结果全为 CANCELLED |
| T2-7 | ?page=1&size=2 | list.length <= 2 |
| T2-8 | 用户 B 查看用户 A 的订单列表 | 列表中不出现 A 的订单（数据隔离） |

### T3 — 订单详情

| ID | 操作 | 预期 |
|---|---|---|
| T3-1 | GET /api/user/orders/{orderNo}（本人） | 200，orderNo 匹配 |
| T3-2 | items 非空 | items.length >= 1 |
| T3-3 | item.productName | 非空字符串（快照写入） |
| T3-4 | item.subtotal = price × quantity | 数值吻合 |
| T3-5 | 用户 B 查用户 A 的订单 | HTTP 403 |
| T3-6 | 不存在的 orderNo | HTTP 404 |

### T4 — 取消订单

| ID | 操作 | 预期 |
|---|---|---|
| T4-1 | 用户 B 取消用户 A 的订单 | HTTP 403 |
| T4-2 | 用户 A 取消自己的 PENDING_PAYMENT 订单 | 200 |
| T4-3 | 取消后订单 status | CANCELLED |
| T4-4 | cancelTime 字段 | 非 null |
| T4-5 | 取消后商品库存 | stockAfter = stockBefore + quantity |
| T4-6 | 已取消订单再次取消 | code=400 |
| T4-7 | 不存在的 orderNo 取消 | code=404 |

### T5 — 商品快照完整性

| ID | 操作 | 预期 |
|---|---|---|
| T5-1 | 下单 quantity=2，等 MQ 落库后查详情 | item.productName 非空 |
| T5-2 | item.subtotal | = price × 2（精度到分） |
| T5-3 | 历史订单（migration 前创建的旧记录） | productName/productImg 为空字符串（不崩溃） |

### T6 — 已支付订单

| ID | 操作 | 预期 |
|---|---|---|
| T6-1 | 支付后 status=PAID 列表可查到该订单 | list 中找到 |
| T6-2 | 已支付订单取消 | code=400 |
| T6-3 | 已支付订单详情 payTime | 非 null（支付宝回调或模拟支付均写入） |

### T7 — 前端 UI（手工）

| ID | 操作 | 预期 |
|---|---|---|
| T7-1 | 登录后 NavBar 出现「我的订单」链接 | 可见，点击跳转 /user/orders |
| T7-2 | 未登录访问 /user/orders | 自动跳转 /login |
| T7-3 | 切换 Tab（全部/待支付/已支付/已取消） | 列表刷新，仅显示对应状态 |
| T7-4 | 点击「查看详情」 | el-dialog 弹出，显示商品明细表格 |
| T7-5 | 点击「取消订单」→ PopConfirm 出现 → 再想想 | 弹窗关闭，订单状态不变 |
| T7-6 | 点击「取消订单」→ PopConfirm 出现 → 确认取消 | 订单变为已取消，列表刷新 |
| T7-7 | 分页：size=5 时翻页 | 数据正确切换 |
| T7-8 | 无订单时 | 显示 el-empty「暂无订单」 |
| T7-9 | 点击「去支付」 | 跳转 /order-pay 并带 orderId/totalPrice |
| T7-10 | 详情弹窗中商品图片 | 如果 productImg 非空，el-image 正常加载 |

---

## 前置条件

1. 执行数据库迁移：
   ```bash
   mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_order_history.sql
   ```
2. 后端 + Redis + RabbitMQ 全部启动
3. 数据库中至少有 1 件上架商品（seed.sql 已提供）
4. （可选）如需测试支付宝 pay_time：配置 `config/application.yml` 中的支付宝参数

---

## 已知边界情况

| 情况 | 说明 |
|---|---|
| migration 前的旧 order_item | product_name/product_img 为空字符串（DEFAULT ''），前端显示「—」正常 |
| MQ Consumer 未启动 | 下单后 status=PROCESSING，T5 快照测试会 SKIP，库存扣减不回滚 |
| 旧订单 payTime | migration 前已支付订单的 payTime 为 NULL，不影响显示 |
| Redis 不可用 | 取消库存恢复仅做 MySQL 侧（stringRedisTemplate 异常仅打 warn，不影响取消结果） |
