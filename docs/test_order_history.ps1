# =============================================================
# Order History Module (U1) Acceptance Test Script
# Run: .\docs\test_order_history.ps1
#
# Prerequisites:
#   - Backend running on :8080  (+ Redis + RabbitMQ)
#   - migration_order_history.sql already executed
# =============================================================

$BASE = "http://localhost:8080/api"

# ---- HTTP helpers -------------------------------------------
function uGet($path, $tok, $qp = $null) {
    $h = @{}
    if ($tok) { $h["Authorization"] = "Bearer $tok" }
    $uri = "$BASE$path"
    if ($qp) {
        $qs = ($qp.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        $uri = "$uri`?$qs"
    }
    Invoke-RestMethod -Uri $uri -Method GET -Headers $h
}
function uPost($path, $tok, $jsonBody) {
    $h = @{ "Content-Type" = "application/json" }
    if ($tok) { $h["Authorization"] = "Bearer $tok" }
    Invoke-RestMethod -Uri "$BASE$path" -Method POST -Headers $h -Body $jsonBody
}

# ---- assertion helpers --------------------------------------
function expectHttp($label, $block, $expected) {
    try {
        $null = (& $block)
        Write-Host "[FAIL] $label  (no HTTP error thrown, expected $expected)" -ForegroundColor Red
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq $expected) {
            Write-Host "[PASS] $label  HTTP $code" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $label  expect=$expected  got=$code" -ForegroundColor Red
        }
    }
}
function expectAppErr($label, $r, $expected = 400) {
    if ($r.code -eq $expected) {
        Write-Host "[PASS] $label  code=$($r.code)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  expect=$expected  got=$($r.code) msg=$($r.msg)" -ForegroundColor Red
    }
}
function ok($label, $r) {
    if ($r.code -eq 200) {
        Write-Host "[PASS] $label" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  code=$($r.code)  msg=$($r.msg)" -ForegroundColor Red
    }
}
function assert($label, $condition, $detail = "") {
    if ($condition) {
        Write-Host "[PASS] $label" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  $detail" -ForegroundColor Red
    }
}

# Poll until order appears in DB (MQ async write, up to maxWait seconds)
function waitForOrder($orderNo, $tok, $maxWait = 15) {
    $elapsed = 0
    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds 1
        $elapsed++
        try {
            $r = uGet "/orders/$orderNo/status" $tok
            if ($r.data.status -ne "PROCESSING") { return $r.data }
        } catch {}
    }
    Write-Host "[WARN] Order $orderNo not in DB after ${maxWait}s (MQ Consumer may be down)" -ForegroundColor DarkYellow
    return $null
}

# =============================================================
# Setup: register two test users A and B
# =============================================================
Write-Host "`n===== Setup: register test users =====" -ForegroundColor Yellow

$TS     = Get-Date -Format 'yyyyMMddHHmmss'
$PhoneA = "137${TS}".Substring(0, 11)
$PhoneB = "138${TS}".Substring(0, 11)

$rA = uPost "/auth/register" $null "{`"phone`":`"$PhoneA`",`"password`":`"123456`",`"nickname`":`"TestA_$TS`"}"
ok "Register UserA  phone=$PhoneA" $rA
$rLoginA = uPost "/auth/login" $null "{`"phone`":`"$PhoneA`",`"password`":`"123456`"}"
$TA = $rLoginA.data.token
Write-Host "       UserA token: $($TA.Substring(0,20))..."

$rB = uPost "/auth/register" $null "{`"phone`":`"$PhoneB`",`"password`":`"123456`",`"nickname`":`"TestB_$TS`"}"
ok "Register UserB  phone=$PhoneB" $rB
$rLoginB = uPost "/auth/login" $null "{`"phone`":`"$PhoneB`",`"password`":`"123456`"}"
$TB = $rLoginB.data.token
Write-Host "       UserB token: $($TB.Substring(0,20))..."

# Fetch product 1 stock before any order
$prodR           = uGet "/products/1" $null
$PROD_ID         = 1
$PROD_STOCK_INIT = $prodR.data.stock
Write-Host "       Product1 stock=$PROD_STOCK_INIT"

# User A: add to cart then create order
$null   = uPost "/cart" $TA "{`"productId`":$PROD_ID,`"quantity`":1}"
$orderR = uPost "/orders" $TA "{`"items`":[{`"productId`":$PROD_ID,`"quantity`":1}]}"
ok "UserA create order" $orderR
$ORDER_NO_A = $orderR.data.orderId
$TOTAL_A    = $orderR.data.totalPrice
Write-Host "       orderNo=$ORDER_NO_A  total=$TOTAL_A"

# Wait for MQ Consumer to persist the order
Write-Host "       Waiting for MQ Consumer..." -ForegroundColor DarkGray
$orderStatus = waitForOrder $ORDER_NO_A $TA
if ($orderStatus) {
    Write-Host "       Order in DB: status=$($orderStatus.status)" -ForegroundColor DarkGray
} else {
    Write-Host "[WARN] MQ Consumer may be down -- snapshot/detail tests may fail" -ForegroundColor DarkYellow
}

# =============================================================
# T1  Auth guard -- no token must return 401
# =============================================================
Write-Host "`n===== T1  Auth Guard =====" -ForegroundColor Yellow

expectHttp "T1-1 GET /user/orders  no-token -> 401"         { uGet  "/user/orders"              $null      } 401
expectHttp "T1-2 GET /user/orders/{no}  no-token -> 401"    { uGet  "/user/orders/$ORDER_NO_A"  $null      } 401
expectHttp "T1-3 POST /user/orders/{no}/cancel no-token -> 401" {
    uPost "/user/orders/$ORDER_NO_A/cancel" $null "{}"
} 401

# =============================================================
# T2  Order list (GET /api/user/orders)
# =============================================================
Write-Host "`n===== T2  Order List =====" -ForegroundColor Yellow

$r = uGet "/user/orders" $TA
ok "T2-1 GET /user/orders -> 200" $r
assert "T2-2 PageVO structure (list/total/page/size)" `
    ($r.data.list -ne $null -and $r.data.PSObject.Properties.Name -contains 'total') `
    "data=$($r.data)"

$found = $r.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_A }
assert "T2-3 Newly created order in list" ($found -ne $null) "orderNo=$ORDER_NO_A"
if ($found) {
    assert "T2-4 itemCount >= 1" ($found.itemCount -ge 1) "itemCount=$($found.itemCount)"
}

# Filter by status
$rP = uGet "/user/orders" $TA @{ status = "PENDING_PAYMENT" }
ok "T2-5 status=PENDING_PAYMENT filter -> 200" $rP
$nonPending = $rP.data.list | Where-Object { $_.status -ne "PENDING_PAYMENT" }
assert "T2-6 All results are PENDING_PAYMENT" ($nonPending.Count -eq 0) "mixed=$($nonPending.Count)"

$rPA = uGet "/user/orders" $TA @{ status = "PAID" }
ok "T2-7 status=PAID filter -> 200" $rPA

$rCA = uGet "/user/orders" $TA @{ status = "CANCELLED" }
ok "T2-8 status=CANCELLED filter -> 200" $rCA

# Pagination
$rPg = uGet "/user/orders" $TA @{ page = 1; size = 2 }
ok "T2-9 page=1, size=2 -> 200" $rPg
assert "T2-10 Max 2 items per page" ($rPg.data.list.Count -le 2) "got=$($rPg.data.list.Count)"

# Data isolation: user B must not see user A orders
$rBOrders = uGet "/user/orders" $TB
$bFoundA  = $rBOrders.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_A }
assert "T2-11 UserB cannot see UserA orders (isolation)" ($bFoundA -eq $null) "should not find orderNo=$ORDER_NO_A"

# =============================================================
# T3  Order detail (GET /api/user/orders/{orderNo})
# =============================================================
Write-Host "`n===== T3  Order Detail =====" -ForegroundColor Yellow

$rD = uGet "/user/orders/$ORDER_NO_A" $TA
ok "T3-1 GET /user/orders/{orderNo} -> 200" $rD
assert "T3-2 orderNo matches"   ($rD.data.orderNo -eq $ORDER_NO_A) "got=$($rD.data.orderNo)"
assert "T3-3 items list not empty" ($rD.data.items.Count -ge 1)  "count=$($rD.data.items.Count)"

if ($rD.data.items.Count -ge 1) {
    $item0 = $rD.data.items[0]
    assert "T3-4 item.productName not empty (snapshot)" `
        ($item0.productName -ne $null -and $item0.productName -ne "") `
        "got='$($item0.productName)'"
    $expectedSub = [math]::Round($item0.price * $item0.quantity, 2)
    $actualSub   = [math]::Round($item0.subtotal, 2)
    assert "T3-5 item.subtotal = price x quantity" ($expectedSub -eq $actualSub) `
        "price=$($item0.price) qty=$($item0.quantity) subtotal=$($item0.subtotal)"
}

# Cross-user: user B reads user A order -> 403
expectHttp "T3-6 UserB reads UserA order -> 403" { uGet "/user/orders/$ORDER_NO_A" $TB } 403

# Non-existent order -> 404
expectHttp "T3-7 Non-existent orderNo -> 404" { uGet "/user/orders/not-exist-no" $TA } 404

# =============================================================
# T4  Cancel order (POST /api/user/orders/{orderNo}/cancel)
# =============================================================
Write-Host "`n===== T4  Cancel Order =====" -ForegroundColor Yellow

# Cross-user: B cancels A order -> 403
expectHttp "T4-1 UserB cancels UserA order -> 403" {
    uPost "/user/orders/$ORDER_NO_A/cancel" $TB "{}"
} 403

# Record stock before cancel
$prodBefore  = uGet "/products/$PROD_ID" $null
$stockBefore = $prodBefore.data.stock
Write-Host "       Stock before cancel=$stockBefore"

# Normal cancel
$rCancel = uPost "/user/orders/$ORDER_NO_A/cancel" $TA "{}"
ok "T4-2 Cancel PENDING_PAYMENT order -> 200" $rCancel

# Verify status + cancelTime
$rAfter = uGet "/user/orders/$ORDER_NO_A" $TA
assert "T4-3 status=CANCELLED after cancel" ($rAfter.data.status -eq "CANCELLED") "got=$($rAfter.data.status)"
assert "T4-4 cancelTime is set" ($rAfter.data.cancelTime -ne $null) "cancelTime=$($rAfter.data.cancelTime)"

# Verify stock restored
Start-Sleep -Seconds 1
$prodAfter  = uGet "/products/$PROD_ID" $null
$stockAfter = $prodAfter.data.stock
Write-Host "       Stock after cancel=$stockAfter  (expected $($stockBefore + 1))"
assert "T4-5 Stock +1 restored after cancel" ($stockAfter -eq $stockBefore + 1) `
    "before=$stockBefore after=$stockAfter"

# Idempotency: cancel already-cancelled order -> code=400
$rCancel2 = uPost "/user/orders/$ORDER_NO_A/cancel" $TA "{}"
expectAppErr "T4-6 Cancel already-cancelled order -> code=400" $rCancel2

# Non-existent order -> code=404
$rNotExist = uPost "/user/orders/not-exist-order/cancel" $TA "{}"
expectAppErr "T4-7 Cancel non-existent order -> code=404" $rNotExist 404

# =============================================================
# T5  Snapshot integrity (quantity=2)
# =============================================================
Write-Host "`n===== T5  Snapshot Integrity =====" -ForegroundColor Yellow

$null    = uPost "/cart" $TA "{`"productId`":$PROD_ID,`"quantity`":2}"
$order2R = uPost "/orders" $TA "{`"items`":[{`"productId`":$PROD_ID,`"quantity`":2}]}"
ok "T5-1 Create order quantity=2" $order2R
$ORDER_NO_2 = $order2R.data.orderId

Write-Host "       Waiting for MQ Consumer..." -ForegroundColor DarkGray
$null = waitForOrder $ORDER_NO_2 $TA

$rD2 = uGet "/user/orders/$ORDER_NO_2" $TA
if ($rD2.code -eq 200 -and $rD2.data.items.Count -ge 1) {
    $item = $rD2.data.items[0]
    assert "T5-2 productName not empty" ($item.productName -ne $null -and $item.productName -ne "") "got='$($item.productName)'"
    $expectedSub2 = [math]::Round($item.price * 2, 2)
    $actualSub2   = [math]::Round($item.subtotal, 2)
    assert "T5-3 subtotal = price x 2" ($expectedSub2 -eq $actualSub2) "price=$($item.price) subtotal=$($item.subtotal)"
} else {
    Write-Host "[SKIP] T5-2/T5-3: order not in DB (MQ Consumer may be down)" -ForegroundColor DarkYellow
}

# =============================================================
# T6  Paid order cannot be cancelled
# =============================================================
Write-Host "`n===== T6  Paid Order =====" -ForegroundColor Yellow

if ($order2R.code -eq 200) {
    $null = waitForOrder $ORDER_NO_2 $TA
    $rPay = uPost "/orders/$ORDER_NO_2/pay" $TA "{}"
    ok "T6-1 Simulate payment -> 200" $rPay

    $rPaidList = uGet "/user/orders" $TA @{ status = "PAID" }
    $paidFound = $rPaidList.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_2 }
    assert "T6-2 Paid order appears in PAID list" ($paidFound -ne $null) "orderNo=$ORDER_NO_2"

    $rCancelPaid = uPost "/user/orders/$ORDER_NO_2/cancel" $TA "{}"
    expectAppErr "T6-3 Cancel paid order -> code=400" $rCancelPaid

    $rPaidDetail = uGet "/user/orders/$ORDER_NO_2" $TA
    assert "T6-4 Detail status=PAID" ($rPaidDetail.data.status -eq "PAID") "got=$($rPaidDetail.data.status)"
}

# =============================================================
Write-Host "`n===== All tests finished =====" -ForegroundColor Yellow
Write-Host "NOTE: T4-5 stock assertion requires Redis to be running." -ForegroundColor DarkGray
Write-Host "NOTE: T3-4/T5-2 snapshot assertions require MQ Consumer to be running." -ForegroundColor DarkGray
