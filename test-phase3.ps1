# Phase 3 API Test Script
# Run: powershell -ExecutionPolicy Bypass -File .\test-phase3.ps1

$BASE = "http://localhost:8080/api"
$PASS = 0; $FAIL = 0
$AMP  = [char]38

function Check($label, $ok, $detail = "") {
    if ($ok) { Write-Host "  [PASS] $label" -ForegroundColor Green; $script:PASS++ }
    else      { Write-Host "  [FAIL] $label $detail" -ForegroundColor Red; $script:FAIL++ }
}
function Title($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function ApiGet($url, $hdrs = @{}) {
    (Invoke-WebRequest -Uri $url -Headers $hdrs -UseBasicParsing).Content | ConvertFrom-Json
}
function ApiPost($url, $obj, $hdrs = @{}) {
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    (Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Headers $hdrs -Body $json -UseBasicParsing).Content | ConvertFrom-Json
}

# 1. Product list
Title "1. GET /api/products"
$r = ApiGet "$BASE/products"
Check "code=200"          ($r.code -eq 200)
$cnt = $r.data.list.Count; Check "list.Count > 0" ($cnt -gt 0) "count=$cnt"
$tot = $r.data.total;     Check "total >= 5"      ($tot -ge 5) "total=$tot"
Check "has name field"    ($null -ne $r.data.list[0].name)
Check "has price field"   ($null -ne $r.data.list[0].price)

# 2. Pagination
Title "2. Pagination pageSize=2"
$pageUrl = "$BASE/products?page=1" + $AMP + "size=2"
$r2 = ApiGet $pageUrl
$c2 = $r2.data.list.Count; Check "list.Count <= 2" ($c2 -le 2) "count=$c2"
Check "total unchanged"   ($r2.data.total -ge 5)

# 3. Product detail
Title "3. GET /api/products/1"
$p = ApiGet "$BASE/products/1"
Check "code=200"          ($p.code -eq 200)
Check "id=1"              ($p.data.id -eq 1)
Check "name not empty"    ($p.data.name -ne "")
Check "price > 0"         ($p.data.price -gt 0)
Check "stock >= 0"        ($p.data.stock -ge 0)
$prodId = $p.data.id
Write-Host "    $($p.data.name)  price:$($p.data.price)  stock:$($p.data.stock)" -ForegroundColor Gray

# 4. Register
Title "4. POST /api/auth/register"
$phone = "138" + (Get-Random -Minimum 10000000 -Maximum 99999999)
$reg = ApiPost "$BASE/auth/register" @{ phone=$phone; password="test123"; nickname="tester" }
Check "code=200"          ($reg.code -eq 200)
$uid = $reg.data; Check "userId > 0" ($uid -gt 0) "userId=$uid"
Write-Host "    phone: $phone" -ForegroundColor Gray

# 5. Login
Title "5. POST /api/auth/login"
$login = ApiPost "$BASE/auth/login" @{ phone=$phone; password="test123" }
Check "code=200"          ($login.code -eq 200)
$tk = $login.data.token
Check "token not empty"   ($tk -ne $null -and $tk -ne "")
$AUTH = @{ Authorization = "Bearer $tk" }
Write-Host "    Token: $($tk.Substring(0,30))..." -ForegroundColor Gray

# 6. Add to cart
Title "6. POST /api/cart (add)"
$a1 = ApiPost "$BASE/cart" @{ productId=$prodId; quantity=2 } $AUTH
Check "1st add code=200"  ($a1.code -eq 200)
$a2 = ApiPost "$BASE/cart" @{ productId=$prodId; quantity=2 } $AUTH
Check "2nd add code=200"  ($a2.code -eq 200)

# 7. Get cart
Title "7. GET /api/cart"
$cart = ApiGet "$BASE/cart" $AUTH
Check "code=200"           ($cart.code -eq 200)
$ic = $cart.data.items.Count; Check "items >= 1" ($ic -ge 1) "count=$ic"
$item = $cart.data.items | Where-Object { $_.productId -eq $prodId } | Select-Object -First 1
Check "product in cart"    ($null -ne $item)
$iq = $item.quantity; Check "qty accumulated = 4" ($iq -eq 4) "qty=$iq"
$expect = [math]::Round($item.price * $item.quantity, 2)
$actual = [math]::Round($item.subtotal, 2)
Check "subtotal correct"   ($actual -eq $expect) "expect=$expect got=$actual"
Check "total exists"       ($null -ne $cart.data.total)
Write-Host "    cart total: $($cart.data.total)" -ForegroundColor Gray

# 8. Create order
Title "8. POST /api/orders"
$orderObj = @{ items = @( @{ productId=$prodId; quantity=1 } ) }
$order = ApiPost "$BASE/orders" $orderObj $AUTH
Check "code=200"           ($order.code -eq 200)
$oid = $order.data.orderId; Check "orderId > 0"    ($oid -gt 0)           "orderId=$oid"
$ost = $order.data.status;  Check "status=PENDING"  ($ost -eq "PENDING")   "status=$ost"
$otp = $order.data.totalPrice; Check "totalPrice > 0" ($otp -gt 0)        "price=$otp"
Write-Host "    orderId:$oid  total:$otp" -ForegroundColor Gray

# 9. Auth guard
Title "9. Auth guard (no token)"
try {
    $unauth = ApiGet "$BASE/cart"
    Check "no-token -> 401"  ($false) "code=$($unauth.code)"
} catch {
    $sc = [int]$_.Exception.Response.StatusCode
    Check "no-token -> 401"  ($sc -eq 401) "status=$sc"
}

# Summary
Write-Host "`n========================================" -ForegroundColor White
$col = if ($FAIL -eq 0) {"Green"} else {"Yellow"}
Write-Host "  PASS $PASS   FAIL $FAIL   total $($PASS+$FAIL)" -ForegroundColor $col
Write-Host "========================================`n" -ForegroundColor White

Write-Host "[ UI Manual Checklist ]  http://localhost:6589" -ForegroundColor Cyan
Write-Host "  [ ] 1. Homepage shows product grid (no login needed)"
Write-Host "  [ ] 2. Search 'iPhone' + Enter -> filtered results"
Write-Host "  [ ] 3. Click product card -> /product/:id detail page"
Write-Host "  [ ] 4. Add to cart (not logged in) -> warning -> redirect login"
Write-Host "  [ ] 5. Login ($phone / test123) -> localStorage has token"
Write-Host "  [ ] 6. Form validation: bad phone/short password shows errors"
Write-Host "  [ ] 7. Add to cart (logged in) -> navbar badge count updates"
Write-Host "  [ ] 8. /cart shows items, subtotals, total, checkout button"
Write-Host "  [ ] 9. Checkout -> /order-success shows orderId"
Write-Host "  [ ] 10. Logout then visit /cart -> redirected to /login"
