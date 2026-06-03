# test-m3.ps1 - M3 Delayed Queue + Order Timeout Cancellation Test Suite
# Usage:
#   .\test-m3.ps1          Run all tests
#   .\test-m3.ps1 -Test 1  Run single test

param([string]$Test = "all")

# ── Configuration ─────────────────────────────────────────────────────────
$API_BASE       = "http://localhost:8080/api"
$MQ_BASE        = "http://localhost:15672/api"
$MQ_CRED        = "Basic " + [Convert]::ToBase64String(
                      [Text.Encoding]::ASCII.GetBytes("admin:admin123"))
$REDIS_CNAME    = "shop-redis"
$MYSQL_USER     = "root"
$MYSQL_PASS     = "redhat"
$MYSQL_DB       = "shop_demo"
$PHONE          = "13800000001"
$PASSWORD       = "123456"
$PRODUCT_ID     = 1
$REDIS_STOCK_KEY = "order:stock:$PRODUCT_ID"
$INIT_STOCK     = 50
$TTL_WAIT       = 65   # seconds - must be > order.timeout-ms/1000 (default 60s)
# ──────────────────────────────────────────────────────────────────────────

function Write-Pass([string]$msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Cyan }
function Write-Step([string]$msg) { Write-Host "`n===== $msg =====" -ForegroundColor Yellow }

function Invoke-Sql([string]$sql) {
    $out = & mysql -u $MYSQL_USER "-p$MYSQL_PASS" $MYSQL_DB -N -e $sql 2>&1 `
           | Where-Object { $_ -notmatch "Warning" }
    return $out
}

function Reset-Stock([int]$stock = $INIT_STOCK) {
    docker exec $REDIS_CNAME redis-cli SET $REDIS_STOCK_KEY $stock | Out-Null
    Invoke-Sql "UPDATE product SET stock=$stock WHERE id=$PRODUCT_ID;" | Out-Null
    Write-Info "Stock reset: MySQL=Redis=$stock"
}

function Get-Token {
    $body = "{""phone"":""$PHONE"",""password"":""$PASSWORD""}"
    $resp = Invoke-RestMethod -Uri "$API_BASE/auth/login" `
                -Method Post -ContentType "application/json" -Body $body
    if (-not $resp.data.token) { throw "Login failed: $($resp.msg)" }
    return $resp.data.token
}

function Place-Order([string]$token) {
    $headers = @{ Authorization = "Bearer $token" }
    $body    = "{""items"":[{""productId"":$PRODUCT_ID,""quantity"":1}]}"
    try {
        $resp = Invoke-RestMethod -Uri "$API_BASE/orders" `
                    -Method Post -Headers $headers -ContentType "application/json" -Body $body
        return $resp.data.orderId
    } catch {
        throw "Place-Order failed: $($_.ErrorDetails.Message)"
    }
}

function Get-OrderStatus([string]$orderId) {
    return (Invoke-Sql "SELECT status FROM ``order`` WHERE order_no='$orderId';" | Select-Object -Last 1)
}

function Get-MysqlStock { return [int]((Invoke-Sql "SELECT stock FROM product WHERE id=$PRODUCT_ID;" | Select-Object -Last 1)) }

function Get-RedisStock { return [int](docker exec $REDIS_CNAME redis-cli GET $REDIS_STOCK_KEY) }

# ── Test 1: Timeout cancellation - status CANCELLED + stocks restored ─────
function Test-1 {
    Write-Step "Test 1 - Order timeout: status PENDING_PAYMENT -> CANCELLED, stocks restored"
    Reset-Stock

    $token = Get-Token
    $oid = $null
    try   { $oid = Place-Order $token }
    catch { Write-Fail "Place-Order error: $_"; return }
    Write-Info "orderId=$oid"

    Start-Sleep -Seconds 3
    $status1 = Get-OrderStatus $oid
    Write-Info "Initial status: $status1"
    if ($status1 -ne "PENDING_PAYMENT") {
        Write-Fail "Expected PENDING_PAYMENT, got: $status1"; return
    }
    Write-Pass "status=PENDING_PAYMENT after order created"

    $stockMysql1 = Get-MysqlStock
    $stockRedis1 = Get-RedisStock
    Write-Info "Stock before timeout: MySQL=$stockMysql1  Redis=$stockRedis1"

    Write-Info "Waiting ${TTL_WAIT}s for TTL to expire..."
    Start-Sleep -Seconds $TTL_WAIT

    $status2   = Get-OrderStatus $oid
    $stockMysql2 = Get-MysqlStock
    $stockRedis2 = Get-RedisStock
    Write-Info "After timeout: status=$status2  MySQL=$stockMysql2  Redis=$stockRedis2"

    if ($status2 -eq "CANCELLED") { Write-Pass "status=CANCELLED" }
    else                          { Write-Fail "status=$status2 (expected CANCELLED)" }

    if ($stockMysql2 -gt $stockMysql1) { Write-Pass "MySQL stock restored ($stockMysql1 -> $stockMysql2)" }
    else                               { Write-Fail "MySQL stock NOT restored ($stockMysql1 -> $stockMysql2)" }

    if ($stockRedis2 -gt $stockRedis1) { Write-Pass "Redis stock restored ($stockRedis1 -> $stockRedis2)" }
    else                               { Write-Fail "Redis stock NOT restored ($stockRedis1 -> $stockRedis2)" }

    if ($stockMysql2 -eq $stockRedis2) { Write-Pass "MySQL and Redis stock consistent ($stockMysql2)" }
    else                               { Write-Fail "MySQL ($stockMysql2) != Redis ($stockRedis2) - inconsistent!" }
}

# ── Test 2: Idempotent - PAID order not cancelled ─────────────────────────
function Test-2 {
    Write-Step "Test 2 - Idempotent: PAID order is NOT cancelled after timeout"
    Reset-Stock

    $token = Get-Token
    $oid = $null
    try   { $oid = Place-Order $token }
    catch { Write-Fail "Place-Order error: $_"; return }
    Write-Info "orderId=$oid"

    Start-Sleep -Seconds 3
    # Manually set to PAID (simulate payment)
    Invoke-Sql "UPDATE ``order`` SET status='PAID' WHERE order_no='$oid';" | Out-Null
    $status1 = Get-OrderStatus $oid
    Write-Info "Status after manual PAID: $status1"

    Write-Info "Waiting ${TTL_WAIT}s for TTL to expire..."
    Start-Sleep -Seconds $TTL_WAIT

    $status2 = Get-OrderStatus $oid
    Write-Info "Status after timeout: $status2"

    if ($status2 -eq "PAID") { Write-Pass "PAID order unchanged (idempotent check works)" }
    else                     { Write-Fail "Status changed to $status2 (idempotent check BROKEN)" }
}

# ── Test 3: RabbitMQ queue visibility ─────────────────────────────────────
function Test-3 {
    Write-Step "Test 3 - RabbitMQ queues visible in management console"

    $headers = @{ Authorization = $MQ_CRED }

    try {
        $delayQ  = Invoke-RestMethod -Uri "$MQ_BASE/queues/%2F/order.delay.queue"  -Headers $headers
        $cancelQ = Invoke-RestMethod -Uri "$MQ_BASE/queues/%2F/order.cancel.queue" -Headers $headers

        Write-Info "order.delay.queue:"
        Write-Info "  messages=$($delayQ.messages)  consumers=$($delayQ.consumers)"
        Write-Info "  x-message-ttl=$($delayQ.arguments.'x-message-ttl')"
        Write-Info "  x-dead-letter-exchange=$($delayQ.arguments.'x-dead-letter-exchange')"
        Write-Info "order.cancel.queue:"
        Write-Info "  messages=$($cancelQ.messages)  consumers=$($cancelQ.consumers)"

        $ttl = $delayQ.arguments.'x-message-ttl'
        if ($ttl -gt 0) { Write-Pass "order.delay.queue exists, TTL=$ttl ms" }
        else            { Write-Fail "order.delay.queue missing or TTL not set" }

        if ($cancelQ) { Write-Pass "order.cancel.queue exists" }
        else          { Write-Fail "order.cancel.queue missing" }

        if ($cancelQ.consumers -ge 1) { Write-Pass "order.cancel.queue has $($cancelQ.consumers) consumer(s)" }
        else                          { Write-Fail "order.cancel.queue has no consumers (app not running?)" }
    } catch {
        Write-Fail "RabbitMQ API error: $_"
        Write-Info "Check: app is running, RabbitMQ at $MQ_BASE, credentials admin:admin123"
    }
}

# ── Test 4: ADR word count ─────────────────────────────────────────────────
function Test-4 {
    Write-Step "Test 4 - ADR word count >= 400"
    $adrPath = Join-Path (Split-Path $PSScriptRoot) "docs/design/mq-order-adr.md"
    if (-not (Test-Path $adrPath)) {
        $adrPath = "docs/design/mq-order-adr.md"
    }
    if (Test-Path $adrPath) {
        $words = (Get-Content $adrPath -Raw) -split '\s+' | Where-Object { $_ -ne '' }
        $count = $words.Count
        Write-Info "ADR path: $adrPath"
        Write-Info "Word count: $count"
        if ($count -ge 400) { Write-Pass "ADR word count=$count (>= 400)" }
        else                { Write-Fail "ADR word count=$count (< 400)" }
    } else {
        Write-Fail "ADR file not found at docs/design/mq-order-adr.md"
    }
}

# ── Entry point ───────────────────────────────────────────────────────────
Write-Host "`nM3 Test Suite  (TTL_WAIT=${TTL_WAIT}s - ensure order.timeout-ms <= $($TTL_WAIT*1000) in application.yml)" -ForegroundColor Magenta
Write-Host "API: $API_BASE  |  DB: $MYSQL_DB  |  MQ: $MQ_BASE"
Write-Host "NOTE: Test 1 and Test 2 each take ~${TTL_WAIT}s to run"

switch ($Test) {
    "1"   { Test-1 }
    "2"   { Test-2 }
    "3"   { Test-3 }
    "4"   { Test-4 }
    "all" {
        Test-3
        Test-4
        Test-1
        Test-2
    }
    default { Write-Host "Usage: .\test-m3.ps1 [-Test 1|2|3|4|all]" }
}

Write-Host "`nDone.`n" -ForegroundColor Magenta
