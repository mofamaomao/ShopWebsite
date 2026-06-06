# =============================================================
# 订单历史模块（U1）验收测试脚本
# Run: .\docs\test_order_history.ps1
#
# 前提：后端已启动 + 已执行 migration_order_history.sql
#      RabbitMQ 正常运行（MQ Consumer 才能落库）
# =============================================================

$BASE = "http://localhost:8080/api"
$amp  = [char]38

# ---- HTTP helpers -------------------------------------------
function uGet($path, $tok, $qp = $null) {
    $h = @{}
    if ($tok) { $h["Authorization"] = "Bearer $tok" }
    $uri = "$BASE$path"
    if ($qp) {
        $qs = ($qp.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join $amp
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

# Poll order status until it appears in DB (MQ async write)
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
# 准备：注册两个测试用户
# =============================================================
Write-Host "`n===== 准备：注册测试用户 =====" -ForegroundColor Yellow

$TS    = Get-Date -Format 'yyyyMMddHHmmss'
$PhoneA = "137${TS}A".Substring(0, 11) -replace 'A', '1'
$PhoneB = "138${TS}B".Substring(0, 11) -replace 'B', '2'

$rA = uPost "/auth/register" $null "{`"phone`":`"$PhoneA`",`"password`":`"123456`",`"nickname`":`"TestA_$TS`"}"
ok "注册用户A  phone=$PhoneA" $rA
$rLoginA = uPost "/auth/login" $null "{`"phone`":`"$PhoneA`",`"password`":`"123456`"}"
$TA = $rLoginA.data.token
Write-Host "       UserA token: $($TA.Substring(0,20))..."

$rB = uPost "/auth/register" $null "{`"phone`":`"$PhoneB`",`"password`":`"123456`",`"nickname`":`"TestB_$TS`"}"
ok "注册用户B  phone=$PhoneB" $rB
$rLoginB = uPost "/auth/login" $null "{`"phone`":`"$PhoneB`",`"password`":`"123456`"}"
$TB = $rLoginB.data.token
Write-Host "       UserB token: $($TB.Substring(0,20))..."

# 查一个有库存的商品（取 product id=1）
$prodR  = uGet "/products/1" $null
$PROD_ID = 1
$PROD_STOCK_BEFORE = $prodR.data.stock
Write-Host "       商品1  stock=$PROD_STOCK_BEFORE"

# User A 加购物车、下单
$null = uPost "/cart" $TA "{`"productId`":$PROD_ID,`"quantity`":1}"
$orderR = uPost "/orders" $TA "{`"items`":[{`"productId`":$PROD_ID,`"quantity`":1}]}"
ok "User A 下单" $orderR
$ORDER_NO_A = $orderR.data.orderId
$TOTAL_A    = $orderR.data.totalPrice
Write-Host "       orderNo=$ORDER_NO_A  total=$TOTAL_A"

# 等待 MQ Consumer 落库
Write-Host "       等待 MQ Consumer 落库..." -ForegroundColor DarkGray
$orderStatus = waitForOrder $ORDER_NO_A $TA
if ($orderStatus) {
    Write-Host "       Order in DB: status=$($orderStatus.status)" -ForegroundColor DarkGray
} else {
    Write-Host "[WARN] MQ Consumer 可能未启动，部分测试将失败" -ForegroundColor DarkYellow
}

# =============================================================
# T1  认证守卫 — 未登录必须 401
# =============================================================
Write-Host "`n===== T1  认证守卫 =====" -ForegroundColor Yellow

expectHttp "T1-1 GET /user/orders 无 token -> 401"   { uGet  "/user/orders"              $null } 401
expectHttp "T1-2 GET /user/orders/{no} 无 token -> 401" { uGet "/user/orders/$ORDER_NO_A" $null } 401
expectHttp "T1-3 POST /user/orders/{no}/cancel 无 token -> 401" {
    uPost "/user/orders/$ORDER_NO_A/cancel" $null "{}"
} 401

# =============================================================
# T2  订单列表 (GET /api/user/orders)
# =============================================================
Write-Host "`n===== T2  订单列表 =====" -ForegroundColor Yellow

$r = uGet "/user/orders" $TA
ok "T2-1 GET /user/orders -> 200" $r
assert "T2-2 返回 PageVO 结构 (list/total/page/size)" `
    ($r.data.list -ne $null -and $r.data.PSObject.Properties.Name -contains 'total') `
    "data=$($r.data)"

$found = $r.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_A }
assert "T2-3 列表包含刚创建的订单" ($found -ne $null) "orderNo=$ORDER_NO_A"
if ($found) {
    assert "T2-4 itemCount 字段存在且 >= 1" ($found.itemCount -ge 1) "itemCount=$($found.itemCount)"
}

# 按状态过滤
$rP = uGet "/user/orders" $TA @{ status="PENDING_PAYMENT" }
ok "T2-5 status=PENDING_PAYMENT 过滤 -> 200" $rP
$nonPending = $rP.data.list | Where-Object { $_.status -ne "PENDING_PAYMENT" }
assert "T2-6 过滤结果全是 PENDING_PAYMENT" ($nonPending.Count -eq 0) "混入了: $($nonPending.Count)"

$rPA = uGet "/user/orders" $TA @{ status="PAID" }
ok "T2-7 status=PAID 过滤 -> 200" $rPA

$rCA = uGet "/user/orders" $TA @{ status="CANCELLED" }
ok "T2-8 status=CANCELLED 过滤 -> 200" $rCA

# 分页参数
$rPg = uGet "/user/orders" $TA @{ page=1; size=2 }
ok "T2-9 page=1&size=2 -> 200" $rPg
assert "T2-10 每页最多 2 条" ($rPg.data.list.Count -le 2) "got=$($rPg.data.list.Count)"

# 用户隔离：B 查不到 A 的订单
$rBOrders = uGet "/user/orders" $TB
$bFoundA = $rBOrders.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_A }
assert "T2-11 用户B看不到用户A的订单（数据隔离）" ($bFoundA -eq $null) "不应出现 orderNo=$ORDER_NO_A"

# =============================================================
# T3  订单详情 (GET /api/user/orders/{orderNo})
# =============================================================
Write-Host "`n===== T3  订单详情 =====" -ForegroundColor Yellow

$rD = uGet "/user/orders/$ORDER_NO_A" $TA
ok "T3-1 GET /user/orders/{orderNo} -> 200" $rD
assert "T3-2 返回 orderNo 正确" ($rD.data.orderNo -eq $ORDER_NO_A) "got=$($rD.data.orderNo)"
assert "T3-3 items 列表非空" ($rD.data.items.Count -ge 1) "count=$($rD.data.items.Count)"

if ($rD.data.items.Count -ge 1) {
    $item0 = $rD.data.items[0]
    assert "T3-4 item.productName 非空（快照）" ($item0.productName -ne $null -and $item0.productName -ne "") "got='$($item0.productName)'"
    assert "T3-5 item.subtotal = price × quantity" `
        ([math]::Round($item0.price * $item0.quantity, 2) -eq [math]::Round($item0.subtotal, 2)) `
        "price=$($item0.price) qty=$($item0.quantity) subtotal=$($item0.subtotal)"
}

# 越权：用户B查用户A的订单 → 403
expectHttp "T3-6 用户B查用户A的订单 -> 403" { uGet "/user/orders/$ORDER_NO_A" $TB } 403

# 不存在的订单 → 404
expectHttp "T3-7 订单不存在 -> 404" { uGet "/user/orders/not-exist-order-no" $TA } 404

# =============================================================
# T4  取消订单 (POST /api/user/orders/{orderNo}/cancel)
# =============================================================
Write-Host "`n===== T4  取消订单 =====" -ForegroundColor Yellow

# 越权取消：B 取消 A 的订单 → 403
expectHttp "T4-1 用户B取消用户A的订单 -> 403" {
    uPost "/user/orders/$ORDER_NO_A/cancel" $TB "{}"
} 403

# 先记录取消前的商品库存
$prodBefore = uGet "/products/$PROD_ID" $null
$stockBefore = $prodBefore.data.stock
Write-Host "       取消前 product$PROD_ID stock=$stockBefore"

# 正常取消
$rCancel = uPost "/user/orders/$ORDER_NO_A/cancel" $TA "{}"
ok "T4-2 取消待支付订单 -> 200" $rCancel

# 验证订单状态变为 CANCELLED
$rAfter = uGet "/user/orders/$ORDER_NO_A" $TA
assert "T4-3 取消后 status=CANCELLED" ($rAfter.data.status -eq "CANCELLED") "got=$($rAfter.data.status)"
assert "T4-4 cancelTime 非空" ($rAfter.data.cancelTime -ne $null) "cancelTime=$($rAfter.data.cancelTime)"

# 验证库存恢复
Start-Sleep -Seconds 1
$prodAfter = uGet "/products/$PROD_ID" $null
$stockAfter = $prodAfter.data.stock
Write-Host "       取消后 product$PROD_ID stock=$stockAfter"
assert "T4-5 取消后库存 +1 已恢复" ($stockAfter -eq $stockBefore + 1) "before=$stockBefore after=$stockAfter"

# 已取消的订单再次取消 → code=400
$rCancel2 = uPost "/user/orders/$ORDER_NO_A/cancel" $TA "{}"
expectAppErr "T4-6 已取消订单再次取消 -> code=400" $rCancel2

# 不存在的订单取消 → 404
$rNotExist = uPost "/user/orders/not-exist-order/cancel" $TA "{}"
expectAppErr "T4-7 不存在的订单取消 -> code=404" $rNotExist 404

# =============================================================
# T5  快照完整性（另下一单，验证 productImg / subtotal）
# =============================================================
Write-Host "`n===== T5  商品快照完整性 =====" -ForegroundColor Yellow

$null = uPost "/cart" $TA "{`"productId`":$PROD_ID,`"quantity`":2}"
$orderR2 = uPost "/orders" $TA "{`"items`":[{`"productId`":$PROD_ID,`"quantity`":2}]}"
ok "T5-1 再次下单（quantity=2）" $orderR2
$ORDER_NO_2 = $orderR2.data.orderId

Write-Host "       等待 MQ Consumer 落库..." -ForegroundColor DarkGray
$null = waitForOrder $ORDER_NO_2 $TA

$rD2 = uGet "/user/orders/$ORDER_NO_2" $TA
if ($rD2.code -eq 200 -and $rD2.data.items.Count -ge 1) {
    $item = $rD2.data.items[0]
    assert "T5-2 productName 有值" ($item.productName -ne $null -and $item.productName -ne "")    "got='$($item.productName)'"
    assert "T5-3 subtotal = price × 2" ([math]::Round($item.price * 2, 2) -eq [math]::Round($item.subtotal, 2)) "price=$($item.price) subtotal=$($item.subtotal)"
} else {
    Write-Host "[SKIP] T5-2/T5-3: 订单未落库（MQ Consumer 可能未启动）" -ForegroundColor DarkYellow
}

# =============================================================
# T6  已支付订单不可取消
# =============================================================
Write-Host "`n===== T6  已支付订单不可取消 =====" -ForegroundColor Yellow

# 用 ORDER_NO_2 走模拟支付
if ($orderR2.code -eq 200) {
    $null = waitForOrder $ORDER_NO_2 $TA
    $rPay = uPost "/orders/$ORDER_NO_2/pay" $TA "{}"
    ok "T6-1 模拟支付 -> 200" $rPay

    $rPaidOrders = uGet "/user/orders" $TA @{ status="PAID" }
    $paidFound = $rPaidOrders.data.list | Where-Object { $_.orderNo -eq $ORDER_NO_2 }
    assert "T6-2 已支付订单出现在 status=PAID 列表" ($paidFound -ne $null) "orderNo=$ORDER_NO_2"

    $rCancelPaid = uPost "/user/orders/$ORDER_NO_2/cancel" $TA "{}"
    expectAppErr "T6-3 已支付订单取消 -> code=400" $rCancelPaid

    # 验证已支付订单详情
    $rPaidDetail = uGet "/user/orders/$ORDER_NO_2" $TA
    assert "T6-4 status=PAID 详情正确" ($rPaidDetail.data.status -eq "PAID") "got=$($rPaidDetail.data.status)"
}

# =============================================================
# 汇总
# =============================================================
Write-Host "`n===== 全部测试完成 =====" -ForegroundColor Yellow
Write-Host "注意：T4-5 库存断言依赖 Redis 库存实时同步，若出现偏差请检查 Redis 是否正常运行" -ForegroundColor DarkGray
