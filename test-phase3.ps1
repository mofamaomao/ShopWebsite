# Phase 3 前端功能测试脚本
# 运行方式：powershell -ExecutionPolicy Bypass -File .\test-phase3.ps1
# 前置条件：后端运行在 8080，前端运行在 6589，Redis 和 MySQL 已启动

$BASE = "http://localhost:8080/api"
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

function Post($url, $body, $headers = @{}) {
    $json = $body | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Headers $headers -Body $json -UseBasicParsing | ConvertFrom-Json
}

function Get-Api($url, $headers = @{}) {
    Invoke-WebRequest -Uri $url -Method GET -Headers $headers -UseBasicParsing | ConvertFrom-Json
}

# ── 1. 商品列表 ──────────────────────────────────────────────────
Section "1. 首页商品列表 /api/products"
$r = Get-Api "$BASE/products"
Check "接口返回 code=200"        ($r.code -eq 200)
Check "data.list 不为空"         ($r.data.list.Count -gt 0)   "list=$($r.data.list.Count)"
Check "data.total >= 5"          ($r.data.total -ge 5)         "total=$($r.data.total)"
Check "商品含 name 字段"         ($null -ne $r.data.list[0].name)
Check "商品含 price 字段"        ($null -ne $r.data.list[0].price)
Check "商品含 stock 字段"        ($null -ne $r.data.list[0].stock)

# ── 2. 分页参数 ──────────────────────────────────────────────────
Section "2. 分页参数支持"
$pageUrl = $BASE + "/products?pageNum=1" + "&pageSize=2"
$r2 = Get-Api $pageUrl
Check "pageSize=2 时 list 最多2条" ($r2.data.list.Count -le 2)  "count=$($r2.data.list.Count)"
Check "total 不因 pageSize 变化"   ($r2.data.total -ge 5)

# ── 3. 商品详情 ──────────────────────────────────────────────────
Section "3. 商品详情 /api/products/1"
$p = Get-Api "$BASE/products/1"
Check "接口返回 code=200"        ($p.code -eq 200)
Check "id=1"                     ($p.data.id -eq 1)
Check "name 非空"                ($p.data.name -ne "")
Check "price > 0"                ($p.data.price -gt 0)
Check "stock >= 0"               ($p.data.stock -ge 0)

$productId = $p.data.id
Write-Host "    商品: $($p.data.name), 价格: $($p.data.price), 库存: $($p.data.stock)" -ForegroundColor Gray

# ── 4. 注册 ──────────────────────────────────────────────────────
Section "4. 注册 /api/auth/register"
$phone = "138" + (Get-Random -Minimum 10000000 -Maximum 99999999)
$regBody = @{ phone = $phone; password = "test123"; nickname = "测试用户" }
$reg = Post "$BASE/auth/register" $regBody
Check "注册返回 code=200"        ($reg.code -eq 200)
Check "返回 userId > 0"          ($reg.data -gt 0)             "userId=$($reg.data)"
Write-Host "    注册手机号: $phone" -ForegroundColor Gray

# ── 5. 登录 ──────────────────────────────────────────────────────
Section "5. 登录 /api/auth/login"
$loginBody = @{ phone = $phone; password = "test123" }
$login = Post "$BASE/auth/login" $loginBody
Check "登录返回 code=200"        ($login.code -eq 200)
Check "返回 token 非空"          ($login.data.token -ne $null -and $login.data.token -ne "")

$TOKEN = $login.data.token
$AUTH = @{ Authorization = "Bearer $TOKEN" }
Write-Host "    Token: $($TOKEN.Substring(0,[Math]::Min(30,$TOKEN.Length)))..." -ForegroundColor Gray

# ── 6. 加入购物车 ────────────────────────────────────────────────
Section "6. 加入购物车 /api/cart (POST)"
$cartBody = @{ productId = $productId; quantity = 2 }
$add = Post "$BASE/cart" $cartBody $AUTH
Check "加购返回 code=200"        ($add.code -eq 200)

$add2 = Post "$BASE/cart" $cartBody $AUTH
Check "重复加购返回 code=200"    ($add2.code -eq 200)

# ── 7. 查看购物车 ────────────────────────────────────────────────
Section "7. 购物车列表 /api/cart (GET)"
$cart = Get-Api "$BASE/cart" $AUTH
Check "购物车返回 code=200"      ($cart.code -eq 200)
Check "items 数量 >= 1"          ($cart.data.items.Count -ge 1)  "count=$($cart.data.items.Count)"
$item = $cart.data.items | Where-Object { $_.productId -eq $productId } | Select-Object -First 1
Check "商品在购物车中"           ($null -ne $item)
Check "数量叠加为 4 (2+2)"       ($item.quantity -eq 4)           "quantity=$($item.quantity)"
Check "subtotal = price x qty"   ([math]::Round($item.subtotal,2) -eq [math]::Round($item.price * $item.quantity, 2))
Check "total 字段存在"           ($null -ne $cart.data.total)
Write-Host "    购物车合计: $($cart.data.total)" -ForegroundColor Gray

# ── 8. 创建订单 ──────────────────────────────────────────────────
Section "8. 创建订单 /api/orders"
$orderItems = @(@{ productId = $productId; quantity = 1 })
$orderBody = @{ items = $orderItems }
$order = Post "$BASE/orders" $orderBody $AUTH
Check "下单返回 code=200"        ($order.code -eq 200)
Check "返回 orderId > 0"         ($order.data.orderId -gt 0)     "orderId=$($order.data.orderId)"
Check "status = PENDING"         ($order.data.status -eq "PENDING")
Check "totalPrice > 0"           ($order.data.totalPrice -gt 0)  "total=$($order.data.totalPrice)"
Write-Host "    订单ID: $($order.data.orderId), 金额: $($order.data.totalPrice)" -ForegroundColor Gray

# ── 9. 未登录访问受保护接口 ──────────────────────────────────────
Section "9. 认证守卫验证"
try {
    $unauth = Get-Api "$BASE/cart"
    Check "未登录购物车返回 401"  ($false) "code=$($unauth.code)"
} catch {
    $status = [int]$_.Exception.Response.StatusCode
    Check "未登录购物车返回 401"  ($status -eq 401) "status=$status"
}

# ── 汇总 ─────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor White
$color = if ($FAIL -eq 0) { "Green" } else { "Yellow" }
Write-Host "  API测试结果: PASS $PASS  FAIL $FAIL  共 $($PASS+$FAIL) 项" -ForegroundColor $color
Write-Host "========================================" -ForegroundColor White

Write-Host ""
Write-Host "【UI 手动验证清单】在浏览器 http://localhost:6589 逐项确认" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [ ] 1. 首页商品网格渲染（不登录可见，含名称/价格/库存）"
Write-Host "  [ ] 2. 搜索框输入 iPhone 回车 -> 只显示 iPhone 商品"
Write-Host "  [ ] 3. 点击商品卡片跳转 /product/:id，页面完整展示"
Write-Host "  [ ] 4. 未登录点击加入购物车 -> 弹提示 -> 跳转登录页"
Write-Host "  [ ] 5. 登录（手机号: $phone / 密码: test123）-> localStorage 有 token"
Write-Host "  [ ] 6. 表单校验：手机号 123 / 密码 12 -> 各自报错"
Write-Host "  [ ] 7. 登录后加入购物车 -> 导航栏角标数字更新"
Write-Host "  [ ] 8. 进入 /cart -> 商品列表、小计、合计金额正确"
Write-Host "  [ ] 9. 点击去结算 -> 跳转 /order-success 显示订单号"
Write-Host "  [ ] 10. 退出登录后访问 /cart -> 自动跳转 /login"
Write-Host ""
