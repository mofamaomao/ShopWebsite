# Phase 3 API 测试脚本
# 运行: powershell -ExecutionPolicy Bypass -File .\test-phase3.ps1

$BASE = "http://localhost:8080/api"
$PASS = 0; $FAIL = 0
$AMP  = [char]38   # & 字符，避免 PowerShell 解析器报错

function Check($label, $ok, $detail = "") {
    if ($ok) { Write-Host "  [PASS] $label" -ForegroundColor Green; $script:PASS++ }
    else      { Write-Host "  [FAIL] $label $detail" -ForegroundColor Red;  $script:FAIL++ }
}
function Title($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function ApiGet($url, $hdrs = @{}) {
    (Invoke-WebRequest -Uri $url -Headers $hdrs -UseBasicParsing).Content | ConvertFrom-Json
}
function ApiPost($url, $obj, $hdrs = @{}) {
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    (Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Headers $hdrs -Body $json -UseBasicParsing).Content | ConvertFrom-Json
}

# ── 1. 商品列表 ──────────────────────────────────────────────────
Title "1. 商品列表 /api/products"
$r = ApiGet "$BASE/products"
Check "code=200"          ($r.code -eq 200)
$cnt = $r.data.list.Count; Check "list.Count > 0" ($cnt -gt 0) "count=$cnt"
$tot = $r.data.total;     Check "total >= 5"      ($tot -ge 5) "total=$tot"
Check "含 name 字段"      ($null -ne $r.data.list[0].name)
Check "含 price 字段"     ($null -ne $r.data.list[0].price)

# ── 2. 分页 ──────────────────────────────────────────────────────
Title "2. 分页参数"
$pageUrl = "$BASE/products?pageNum=1" + $AMP + "pageSize=2"
$r2 = ApiGet $pageUrl
$c2 = $r2.data.list.Count; Check "pageSize=2 -> list<=2" ($c2 -le 2) "count=$c2"
Check "total 不变"        ($r2.data.total -ge 5)

# ── 3. 商品详情 ──────────────────────────────────────────────────
Title "3. 商品详情 /api/products/1"
$p = ApiGet "$BASE/products/1"
Check "code=200"          ($p.code -eq 200)
Check "id=1"              ($p.data.id -eq 1)
Check "name 非空"         ($p.data.name -ne "")
Check "price > 0"         ($p.data.price -gt 0)
Check "stock >= 0"        ($p.data.stock -ge 0)
$pid = $p.data.id
Write-Host "    $($p.data.name)  价格:$($p.data.price)  库存:$($p.data.stock)" -ForegroundColor Gray

# ── 4. 注册 ──────────────────────────────────────────────────────
Title "4. 注册 /api/auth/register"
$phone = "138" + (Get-Random -Minimum 10000000 -Maximum 99999999)
$reg = ApiPost "$BASE/auth/register" @{ phone=$phone; password="test123"; nickname="测试用户" }
Check "code=200"          ($reg.code -eq 200)
$uid = $reg.data;  Check "userId > 0" ($uid -gt 0) "userId=$uid"
Write-Host "    手机号: $phone" -ForegroundColor Gray

# ── 5. 登录 ──────────────────────────────────────────────────────
Title "5. 登录 /api/auth/login"
$login = ApiPost "$BASE/auth/login" @{ phone=$phone; password="test123" }
Check "code=200"          ($login.code -eq 200)
$tk = $login.data.token
Check "token 非空"        ($tk -ne $null -and $tk -ne "")
$AUTH = @{ Authorization = "Bearer $tk" }
Write-Host "    Token: $($tk.Substring(0,30))..." -ForegroundColor Gray

# ── 6. 加入购物车 ────────────────────────────────────────────────
Title "6. 加入购物车 /api/cart"
$a1 = ApiPost "$BASE/cart" @{ productId=$pid; quantity=2 } $AUTH
Check "第1次加购 code=200" ($a1.code -eq 200)
$a2 = ApiPost "$BASE/cart" @{ productId=$pid; quantity=2 } $AUTH
Check "第2次加购 code=200" ($a2.code -eq 200)

# ── 7. 购物车列表 ────────────────────────────────────────────────
Title "7. 购物车 GET /api/cart"
$cart = ApiGet "$BASE/cart" $AUTH
Check "code=200"           ($cart.code -eq 200)
$ic = $cart.data.items.Count; Check "items >= 1" ($ic -ge 1) "count=$ic"
$item = $cart.data.items | Where-Object { $_.productId -eq $pid } | Select-Object -First 1
Check "商品在购物车中"     ($null -ne $item)
$iq = $item.quantity; Check "数量叠加=4" ($iq -eq 4) "qty=$iq"
$expect = [math]::Round($item.price * $item.quantity, 2)
$actual = [math]::Round($item.subtotal, 2)
Check "subtotal 正确"      ($actual -eq $expect) "expect=$expect actual=$actual"
Check "total 存在"         ($null -ne $cart.data.total)
Write-Host "    合计: $($cart.data.total)" -ForegroundColor Gray

# ── 8. 创建订单 ──────────────────────────────────────────────────
Title "8. 创建订单 /api/orders"
$orderObj = @{ items = @( @{ productId=$pid; quantity=1 } ) }
$order = ApiPost "$BASE/orders" $orderObj $AUTH
Check "code=200"           ($order.code -eq 200)
$oid = $order.data.orderId; Check "orderId > 0"   ($oid -gt 0)   "orderId=$oid"
$ost = $order.data.status;  Check "status=PENDING" ($ost -eq "PENDING") "status=$ost"
$otp = $order.data.totalPrice; Check "totalPrice > 0" ($otp -gt 0) "price=$otp"
Write-Host "    订单ID:$oid  金额:$otp" -ForegroundColor Gray

# ── 9. 未登录守卫 ────────────────────────────────────────────────
Title "9. 认证守卫"
try {
    $unauth = ApiGet "$BASE/cart"
    Check "未登录返回401" ($false) "code=$($unauth.code)"
} catch {
    $sc = [int]$_.Exception.Response.StatusCode
    Check "未登录返回401" ($sc -eq 401) "status=$sc"
}

# ── 汇总 ─────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor White
$col = if ($FAIL -eq 0) {"Green"} else {"Yellow"}
Write-Host "  PASS $PASS   FAIL $FAIL   共 $($PASS+$FAIL) 项" -ForegroundColor $col
Write-Host "========================================`n" -ForegroundColor White

Write-Host "【UI 手动验证清单】浏览器打开 http://localhost:6589" -ForegroundColor Cyan
Write-Host "  [ ] 1. 首页商品网格可见（不登录也能看到）"
Write-Host "  [ ] 2. 搜索 iPhone 回车 -> 只显示含 iPhone 商品"
Write-Host "  [ ] 3. 点商品卡片 -> 跳 /product/:id，展示详情"
Write-Host "  [ ] 4. 未登录点加入购物车 -> 弹提示 -> 跳登录页"
Write-Host "  [ ] 5. 登录 ($phone / test123) -> localStorage 有 token"
Write-Host "  [ ] 6. 表单校验：手机号123 / 密码12 -> 各自报错"
Write-Host "  [ ] 7. 登录后加购 -> 导航栏角标数字更新"
Write-Host "  [ ] 8. /cart 页面：列表+小计+合计+去结算按钮"
Write-Host "  [ ] 9. 去结算 -> /order-success 显示订单号"
Write-Host "  [ ] 10. 退出登录后访问 /cart -> 重定向到 /login"
