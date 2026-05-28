# Phase 3 前端功能测试脚本
# 运行方式：在 PowerShell 中执行 .\test-phase3.ps1
# 前置条件：后端运行在 8080，前端运行在 6589，Redis 和 MySQL 已启动

$BASE = "http://localhost:8080/api"
$FRONT = "http://localhost:6589"
$PASS = 0
$FAIL = 0

function Check($label, $condition, $detail = "") {
    if ($condition) {
        Write-Host "  [PASS] $label" -ForegroundColor Green
        $script:PASS++
    } else {
        Write-Host "  [FAIL] $label  $detail" -ForegroundColor Red
        $script:FAIL++
    }
}

function Section($title) {
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
}

# ── 1. 商品列表接口 ──────────────────────────────────────────────
Section "1. 首页商品列表 /api/products"
$r = (Invoke-WebRequest "$BASE/products" -UseBasicParsing | ConvertFrom-Json)
Check "接口返回 code=200"        ($r.code -eq 200)
Check "data.list 不为空"         ($r.data.list.Count -gt 0)          "list=$($r.data.list.Count)"
Check "data.total >= 5"          ($r.data.total -ge 5)               "total=$($r.data.total)"
Check "商品含 name 字段"         ($r.data.list[0].name -ne $null)
Check "商品含 price 字段"        ($r.data.list[0].price -ne $null)
Check "商品含 stock 字段"        ($r.data.list[0].stock -ne $null)

# ── 2. 分页参数 ──────────────────────────────────────────────────
Section "2. 分页参数支持"
$r2 = (Invoke-WebRequest "$BASE/products?pageNum=1&pageSize=2" -UseBasicParsing | ConvertFrom-Json)
Check "pageSize=2 时 list 最多2条" ($r2.data.list.Count -le 2)       "count=$($r2.data.list.Count)"
Check "total 不因 pageSize 变化"   ($r2.data.total -ge 5)

# ── 3. 商品详情 ──────────────────────────────────────────────────
Section "3. 商品详情 /api/products/1"
$p = (Invoke-WebRequest "$BASE/products/1" -UseBasicParsing | ConvertFrom-Json)
Check "接口返回 code=200"        ($p.code -eq 200)
Check "id=1"                     ($p.data.id -eq 1)
Check "name 非空"                ($p.data.name -ne "")
Check "price > 0"                ($p.data.price -gt 0)
Check "stock >= 0"               ($p.data.stock -ge 0)

$productId = $p.data.id
$productName = $p.data.name
Write-Host "    商品: $productName, 价格: $($p.data.price), 库存: $($p.data.stock)" -ForegroundColor Gray

# ── 4. 注册新用户 ────────────────────────────────────────────────
Section "4. 注册 /api/auth/register"
$phone = "138" + (Get-Random -Minimum 10000000 -Maximum 99999999)
$body = "{`"phone`":`"$phone`",`"password`":`"test123`",`"nickname`":`"测试用户`"}"
$reg = (Invoke-WebRequest -Uri "$BASE/auth/register" -Method POST -ContentType "application/json" -Body $body -UseBasicParsing | ConvertFrom-Json)
Check "注册返回 code=200"        ($reg.code -eq 200)
Check "返回 userId(data>0)"      ($reg.data -gt 0)                   "userId=$($reg.data)"
Write-Host "    注册手机号: $phone" -ForegroundColor Gray

# ── 5. 登录 ──────────────────────────────────────────────────────
Section "5. 登录 /api/auth/login"
$loginBody = "{`"phone`":`"$phone`",`"password`":`"test123`"}"
$login = (Invoke-WebRequest -Uri "$BASE/auth/login" -Method POST -ContentType "application/json" -Body $loginBody -UseBasicParsing | ConvertFrom-Json)
Check "登录返回 code=200"        ($login.code -eq 200)
Check "返回 token 非空"          ($login.data.token -ne $null -and $login.data.token -ne "")

$TOKEN = $login.data.token
$AUTH = @{ Authorization = "Bearer $TOKEN" }
Write-Host "    Token: $($TOKEN.Substring(0,[Math]::Min(30,$TOKEN.Length)))..." -ForegroundColor Gray

# ── 6. 加入购物车 ────────────────────────────────────────────────
Section "6. 加入购物车 /api/cart (POST)"
$cartBody = "{`"productId`":$productId,`"quantity`":2}"
$add = (Invoke-WebRequest -Uri "$BASE/cart" -Method POST -ContentType "application/json" -Headers $AUTH -Body $cartBody -UseBasicParsing | ConvertFrom-Json)
Check "加购返回 code=200"        ($add.code -eq 200)

# 再加一次，验证幂等叠加
$add2 = (Invoke-WebRequest -Uri "$BASE/cart" -Method POST -ContentType "application/json" -Headers $AUTH -Body $cartBody -UseBasicParsing | ConvertFrom-Json)
Check "重复加购返回 code=200"    ($add2.code -eq 200)

# ── 7. 查看购物车 ────────────────────────────────────────────────
Section "7. 购物车列表 /api/cart (GET)"
$cart = (Invoke-WebRequest -Uri "$BASE/cart" -Method GET -Headers $AUTH -UseBasicParsing | ConvertFrom-Json)
Check "购物车返回 code=200"      ($cart.code -eq 200)
Check "items 数量 >= 1"          ($cart.data.items.Count -ge 1)       "count=$($cart.data.items.Count)"
$item = $cart.data.items | Where-Object { $_.productId -eq $productId } | Select-Object -First 1
Check "商品在购物车中"           ($item -ne $null)
Check "数量叠加为 4 (2+2)"       ($item.quantity -eq 4)               "quantity=$($item.quantity)"
Check "subtotal = price * qty"   ($item.subtotal -eq [math]::Round($item.price * $item.quantity, 2))
Check "total 字段存在"           ($cart.data.total -ne $null)
Write-Host "    购物车合计: ¥$($cart.data.total)" -ForegroundColor Gray

# ── 8. 创建订单 ──────────────────────────────────────────────────
Section "8. 创建订单 /api/orders"
$orderBody = "{`"items`":[{`"productId`":$productId,`"quantity`":1}]}"
$order = (Invoke-WebRequest -Uri "$BASE/orders" -Method POST -ContentType "application/json" -Headers $AUTH -Body $orderBody -UseBasicParsing | ConvertFrom-Json)
Check "下单返回 code=200"        ($order.code -eq 200)
Check "返回 orderId > 0"         ($order.data.orderId -gt 0)          "orderId=$($order.data.orderId)"
Check "status = PENDING"         ($order.data.status -eq "PENDING")
Check "totalPrice > 0"           ($order.data.totalPrice -gt 0)       "total=¥$($order.data.totalPrice)"
Write-Host "    订单ID: $($order.data.orderId), 金额: ¥$($order.data.totalPrice)" -ForegroundColor Gray

# ── 9. 未登录访问购物车接口 ──────────────────────────────────────
Section "9. 认证守卫验证"
try {
    $unauth = (Invoke-WebRequest -Uri "$BASE/cart" -Method GET -UseBasicParsing | ConvertFrom-Json)
    Check "未登录购物车返回 401"  ($unauth.code -eq 401 -or $false)
} catch {
    Check "未登录购物车返回 401"  ($_.Exception.Response.StatusCode -eq 401) "status=$($_.Exception.Response.StatusCode)"
}

# ── 汇总 ─────────────────────────────────────────────────────────
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White
Write-Host "  API测试结果：PASS $PASS  FAIL $FAIL  共 $($PASS+$FAIL) 项" -ForegroundColor $(if ($FAIL -eq 0) {"Green"} else {"Yellow"})
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor White

# ── UI 手动测试清单 ───────────────────────────────────────────────
Write-Host @"

【UI 手动验证清单】在浏览器 http://localhost:6589 逐项确认

  □ 1. 首页商品网格
       · 打开首页，可以看到多个商品卡片（含名称、价格）
       · 不登录也能看到商品列表

  □ 2. 关键词搜索
       · 在顶部搜索框输入 "iPhone" 回车
       · 列表只显示包含 iPhone 的商品
       · 清空搜索框回车，恢复全部商品

  □ 3. 商品详情
       · 点击任意商品卡片，跳转到 /product/:id
       · 页面展示商品名称、价格、库存、描述
       · 有数量选择器和"加入购物车"按钮

  □ 4. 未登录加入购物车
       · 不登录状态下点击"加入购物车"
       · 弹出"请先登录"提示，自动跳转登录页

  □ 5. 登录功能
       · 输入手机号 $phone / 密码 test123
       · 登录成功后跳转首页，导航栏显示"用户"字样
       · 打开 DevTools → Application → localStorage，确认有 token

  □ 6. 注册表单校验
       · 手机号输入 123（格式错误），点登录，出现校验提示
       · 密码输入 123（少于6位），出现校验提示

  □ 7. 登录后加入购物车 + 角标
       · 登录状态下进入商品详情，加入购物车
       · 导航栏购物车图标右上角出现数字角标

  □ 8. 购物车页面
       · 点击导航栏购物车图标，跳转 /cart
       · 列表显示商品名、数量、小计，底部有合计金额
       · "去结算"按钮可见

  □ 9. 下单流程
       · 购物车页点击"去结算"
       · 跳转到 /order-success，展示订单号和金额

  □ 10. 路由守卫
        · 退出登录后直接访问 http://localhost:6589/cart
        · 自动重定向到 /login

"@ -ForegroundColor White
