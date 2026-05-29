# Phase 4 Acceptance Test Script
# TC-01/03/04/05/06/07: API automation
# TC-02/UI parts: manual steps printed at end
# Run: powershell -ExecutionPolicy Bypass -File .\test-phase4.ps1

param(
    [string]$BackendUrl = "http://localhost:8080/api",
    [string]$FrontendUrl = "http://localhost:6589"
)

$PASS = 0; $FAIL = 0; $AMP = [char]38
$Results = @()

function Check($tc, $label, $ok, $detail = "") {
    $status = if ($ok) { "PASS" } else { "FAIL" }
    $color  = if ($ok) { "Green" } else { "Red" }
    Write-Host "  [$status] $tc $label $detail" -ForegroundColor $color
    if ($ok) { $script:PASS++ } else { $script:FAIL++ }
    $script:Results += [PSCustomObject]@{ TC=$tc; Label=$label; Status=$status; Detail=$detail }
}

function Title($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function ApiGet($url, $hdrs = @{}) {
    try {
        (Invoke-WebRequest -Uri $url -Headers $hdrs -UseBasicParsing).Content | ConvertFrom-Json
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        [PSCustomObject]@{ code=$sc; __error=$true }
    }
}

function ApiPost($url, $obj, $hdrs = @{}) {
    try {
        $json = $obj | ConvertTo-Json -Compress -Depth 5
        (Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Headers $hdrs -Body $json -UseBasicParsing).Content | ConvertFrom-Json
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        [PSCustomObject]@{ code=$sc; __error=$true }
    }
}

# ─────────────────────────────────────────────────────────────────
# TC-01: Register + Login
# ─────────────────────────────────────────────────────────────────
Title "TC-01: Register + Login"
$phone = "139" + (Get-Random -Minimum 10000000 -Maximum 99999999)

$reg = ApiPost "$BackendUrl/auth/register" @{ phone=$phone; password="Test1234"; nickname="QA-User" }
Check "TC-01" "register code=200"       ($reg.code -eq 200)
Check "TC-01" "register returns userId" ($reg.data -gt 0) "userId=$($reg.data)"

$login = ApiPost "$BackendUrl/auth/login" @{ phone=$phone; password="Test1234" }
Check "TC-01" "login code=200"          ($login.code -eq 200)
$tk = $login.data.token
Check "TC-01" "token not empty"         ($tk -ne $null -and $tk.Length -gt 20) "len=$($tk.Length)"

$AUTH = @{ Authorization = "Bearer $tk" }
Write-Host "    phone=$phone  token=${tk}.Substring(0,20)..." -ForegroundColor Gray

# ─────────────────────────────────────────────────────────────────
# TC-02: Keyword search (API layer)
# ─────────────────────────────────────────────────────────────────
Title "TC-02: Keyword search (API)"
$kwUrl  = "$BackendUrl/products?keyword=iPhone"
$kwRes  = ApiGet $kwUrl
Check "TC-02" "keyword=iPhone code=200"  ($kwRes.code -eq 200)
$hits    = @($kwRes.data.list | Where-Object { $_.name -match "iPhone" -or $_.description -match "iPhone" })
$allList = @($kwRes.data.list)
Check "TC-02" "all results match keyword" ($hits.Count -eq $allList.Count) "hits=$($hits.Count) total=$($allList.Count)"

$noHitUrl = "$BackendUrl/products?keyword=XYZNOTEXIST999"
$noHit = ApiGet $noHitUrl
Check "TC-02" "no-match returns empty list" ($noHit.data.list.Count -eq 0) "count=$($noHit.data.list.Count)"

# ─────────────────────────────────────────────────────────────────
# TC-03: Add to cart + view
# ─────────────────────────────────────────────────────────────────
Title "TC-03: Add to cart + view"
$products = ApiGet "$BackendUrl/products"
$prodId   = $products.data.list[0].id
$prodPrice = $products.data.list[0].price

$add = ApiPost "$BackendUrl/cart" @{ productId=$prodId; quantity=2 } $AUTH
Check "TC-03" "add to cart code=200" ($add.code -eq 200)

$cart = ApiGet "$BackendUrl/cart" $AUTH
Check "TC-03" "cart returns items"   ($cart.data.items.Count -ge 1)
$item = $cart.data.items | Where-Object { $_.productId -eq $prodId } | Select-Object -First 1
Check "TC-03" "product in cart"      ($null -ne $item)
$expectedSub = [math]::Round($item.price * $item.quantity, 2)
$actualSub   = [math]::Round($item.subtotal, 2)
Check "TC-03" "subtotal correct"     ($actualSub -eq $expectedSub) "expect=$expectedSub got=$actualSub"
Check "TC-03" "cart total > 0"       ($cart.data.total -gt 0) "total=$($cart.data.total)"

# ─────────────────────────────────────────────────────────────────
# TC-04: Checkout main flow
# ─────────────────────────────────────────────────────────────────
Title "TC-04: Checkout + stock reduction"

$beforeProd = ApiGet "$BackendUrl/products/$prodId"
$stockBefore = $beforeProd.data.stock
Write-Host "    stock before order: $stockBefore" -ForegroundColor Gray

$orderObj = @{ items = @( @{ productId=$prodId; quantity=1 } ) }
$order = ApiPost "$BackendUrl/orders" $orderObj $AUTH
Check "TC-04" "create order code=200"   ($order.code -eq 200)
Check "TC-04" "orderId > 0"             ($order.data.orderId -gt 0) "orderId=$($order.data.orderId)"
Check "TC-04" "status=PENDING"          ($order.data.status -eq "PENDING")
Check "TC-04" "totalPrice = prodPrice"  ($order.data.totalPrice -eq $prodPrice) "expect=$prodPrice got=$($order.data.totalPrice)"

$afterProd = ApiGet "$BackendUrl/products/$prodId"
$stockAfter = $afterProd.data.stock
Check "TC-04" "stock decreased by 1"    ($stockAfter -eq ($stockBefore - 1)) "before=$stockBefore after=$stockAfter"

# ─────────────────────────────────────────────────────────────────
# TC-05: Unauthenticated redirect (API layer)
# ─────────────────────────────────────────────────────────────────
Title "TC-05: Unauth guard"
$unauthCart  = ApiGet "$BackendUrl/cart"
Check "TC-05" "no-token GET /cart -> 401"  ($unauthCart.code -eq 401) "code=$($unauthCart.code)"

$unauthOrder = ApiPost "$BackendUrl/orders" @{ items=@(@{productId=1;quantity=1}) }
Check "TC-05" "no-token POST /orders -> 401" ($unauthOrder.code -eq 401) "code=$($unauthOrder.code)"

# ─────────────────────────────────────────────────────────────────
# TC-06: Oversell stress test (5 concurrent requests, qty=1 each)
# NOTE: pre-condition -> set product stock=3 in MySQL first:
#   UPDATE product SET stock=3 WHERE id=<prodId>;
# ─────────────────────────────────────────────────────────────────
Title "TC-06: Oversell stress test (concurrent 5 requests)"
Write-Host "  Pre-condition: stock of product $prodId must be set to 3 in MySQL" -ForegroundColor Yellow
Write-Host "  SQL: UPDATE product SET stock=3 WHERE id=$prodId;" -ForegroundColor Yellow
Write-Host "  Press Enter after updating stock, or Ctrl+C to skip..." -ForegroundColor Yellow
$null = Read-Host

$stockNow = (ApiGet "$BackendUrl/products/$prodId").data.stock
Write-Host "  Current stock: $stockNow" -ForegroundColor Gray

if ($stockNow -lt 3) {
    Write-Host "  [SKIP] TC-06 skipped: stock=$stockNow (need 3)" -ForegroundColor Yellow
} else {
    $orderBody = @{ items = @(@{ productId=$prodId; quantity=1 }) } | ConvertTo-Json -Compress -Depth 5
    $bearer = "Bearer $tk"

    Write-Host "  Firing 5 concurrent order requests..." -ForegroundColor Gray
    $jobs = 1..5 | ForEach-Object {
        $idx = $_
        Start-Job -ScriptBlock {
            param($url, $body, $auth, $n)
            try {
                $res = (Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" `
                    -Headers @{ Authorization=$auth } -Body $body -UseBasicParsing).Content | ConvertFrom-Json
                "$n code=$($res.code) orderId=$($res.data.orderId)"
            } catch {
                "$n error=$($_.Exception.Response.StatusCode)"
            }
        } -ArgumentList "$BackendUrl/orders", $orderBody, $bearer, $idx
    }

    $outputs = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    $outputs | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

    $successCount = ($outputs | Where-Object { $_ -match "orderId=\d+" -and $_ -notmatch "orderId=" }).Count
    # recount properly
    $successCount = 0
    $outputs | ForEach-Object {
        if ($_ -match "orderId=(\d+)" -and $Matches[1] -ne "" -and [int]$Matches[1] -gt 0) { $successCount++ }
    }

    $finalStock = (ApiGet "$BackendUrl/products/$prodId").data.stock
    Write-Host "  Final stock: $finalStock  Successful orders: $successCount" -ForegroundColor Gray

    Check "TC-06" "final stock >= 0 (no negative)" ($finalStock -ge 0)            "stock=$finalStock"
    Check "TC-06" "success orders <= 3"             ($successCount -le 3)          "success=$successCount"
    Check "TC-06" "success orders + finalStock = 3" (($successCount + $finalStock) -eq 3) "succ=$successCount stock=$finalStock"
}

# ─────────────────────────────────────────────────────────────────
# TC-07: Invalid token
# ─────────────────────────────────────────────────────────────────
Title "TC-07: Invalid token"
$badAuth  = @{ Authorization = "Bearer this.is.a.fake.token.xyz" }
$badCart  = ApiGet "$BackendUrl/cart" $badAuth
Check "TC-07" "bad token -> 401"  ($badCart.code -eq 401) "code=$($badCart.code)"

$expiredAuth = @{ Authorization = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI5OTkiLCJpYXQiOjE2MDAwMDAwMDAsImV4cCI6MTYwMDAwMDAwMX0.fake" }
$expCart  = ApiGet "$BackendUrl/cart" $expiredAuth
Check "TC-07" "expired token -> 401" ($expCart.code -eq 401) "code=$($expCart.code)"

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor White
$col = if ($FAIL -eq 0) { "Green" } else { "Yellow" }
Write-Host "  PASS $PASS   FAIL $FAIL   total $($PASS+$FAIL)" -ForegroundColor $col
Write-Host "========================================" -ForegroundColor White

Write-Host "`n[ Results Table ]" -ForegroundColor Cyan
$Results | Format-Table TC, Label, Status, Detail -AutoSize

Write-Host "`n[ UI Manual Checklist ]  $FrontendUrl" -ForegroundColor Cyan
Write-Host "  TC-01 [ ] Navbar shows nickname after register+login"
Write-Host "  TC-01 [ ] localStorage has 'token' key (DevTools > Application)"
Write-Host "  TC-02 [ ] Search 'iPhone' -> only iPhone products shown"
Write-Host "  TC-02 [ ] Search 'XYZNOTEXIST999' -> empty state displayed"
Write-Host "  TC-03 [ ] Cart badge on navbar increments after add-to-cart"
Write-Host "  TC-03 [ ] Cart page shows correct item list and total"
Write-Host "  TC-04 [ ] Checkout -> /order-success shows orderId"
Write-Host "  TC-05 [ ] Logout -> visit /cart -> auto redirect to /login"
Write-Host "  TC-07 [ ] After clearing token in DevTools -> any auth page redirects to /login"
