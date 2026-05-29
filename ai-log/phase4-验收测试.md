# Phase 4 归档 — 验收测试

## 测试结论
**24/24 PASS，零 FAIL，验收通过。**

---

## 测试用例结果

| 用例 | 描述 | 状态 | 关键数据 |
|------|------|------|----------|
| TC-01 | 用户注册+登录，token 写入 | PASS | userId=8, token len=125 |
| TC-02 | keyword=iPhone 搜索，空结果状态 | PASS | hits=1/total=1, no-match count=0 |
| TC-03 | 加入购物车，小计/合计计算 | PASS | subtotal=1198.00 |
| TC-04 | 下单主链路，库存扣减验证 | PASS | orderId=19, stock 135→134 |
| TC-05 | 未登录访问受保护接口返回 401 | PASS | /cart 和 /orders 均 401 |
| TC-06 | 超卖压测：stock=3，5 并发请求 | PASS | 成功 3，拒绝 2，最终 stock=0 |
| TC-07 | 伪造/过期 token 返回 401 | PASS | 两种无效 token 均 401 |

---

## TC-06 超卖压测详情

```
stock 设为 3，同时发出 5 个下单请求（每单 qty=1）

请求 1 -> code=200 orderId=20  ✓
请求 2 -> code=200 orderId=21  ✓
请求 3 -> code=200 orderId=22  ✓
请求 4 -> code=1003            ✗ 库存不足
请求 5 -> code=1003            ✗ 库存不足

最终库存: 0（无负库存）
成功订单: 3 = 初始库存
```

SELECT FOR UPDATE 行锁在并发场景下正确保证了原子性，无超卖。

---

## 测试过程中发现并修复的问题

| 问题 | 定性 | 修复 |
|------|------|------|
| TC-02 脚本：单结果 `.Count` 返回 null | 测试脚本 Bug | `@(Where-Object)` 强制数组 |
| TC-06 首轮 stock 未设为 3 | 前置条件未满足 | 补执行 SQL 后重测通过 |
| `$pid` 为 PowerShell 保留变量 | 测试脚本 Bug | 改名 `$prodId` |
| 脚本中文字符编码导致 `'` 截断 | 测试脚本 Bug | 全部改为 ASCII label |
| URL 中 `&` 被 PS 解析器拦截 | 测试脚本 Bug | `$AMP = [char]38` |

---

## UI 手动验收（人工确认）

- [x] 首页商品网格不登录可见
- [x] 搜索框输入关键词回车，列表联动更新
- [x] 点击商品跳详情页，展示完整信息
- [x] 未登录点加入购物车弹提示并跳转登录
- [x] 登录后导航栏显示昵称，localStorage 有 token
- [x] 加购后导航栏角标数字更新
- [x] 购物车页商品列表、小计、合计正确
- [x] 去结算跳转 /order-success 显示订单号
- [x] 退出后访问 /cart 自动跳转 /login
- [x] 无效 token 清除后跳转登录页

---

## 项目完成状态

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 1 | 环境搭建、三表 DDL、健康检查 | DONE |
| Phase 2 | 7 个后端接口（JWT/Redis/SELECT FOR UPDATE） | DONE |
| Phase 3 | Vue 前端全页面开发与 API 对接 | DONE |
| Phase 4 | 验收测试 24/24 全通过 | DONE |
