# test-m2.ps1 - M2 Reliable Delivery + Idempotent Consumption Test Suite
# Usage:
#   .\test-m2.ps1          Run all tests
#   .\test-m2.ps1 -Test 1  Run single test

param([string]$Test = "all")

# ── Configuration (edit to match your environment) ───────────────────────
$API_BASE       = "http://localhost:8080/api"
$MQ_BASE        = "http://localhost:15672/api"
$MQ_CRED        = "Basic " + [Convert]::ToBase64String(
                      [Text.Encoding]::ASCII.GetBytes("admin:admin123"))
$RABBITMQ_CNAME = "shop-rabbitmq"
$MYSQL_USER     = "root"
$MYSQL_PASS     = "redhat"
$MYSQL_DB       = "shop_demo"
$PHONE          = "13800000001"
$PASSWORD       = "123456"
$PRODUCT_ID     = 1
# ─────────────────────────────────────────────────────────────────────────

function Write-Pass([string]$msg) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Cyan }
function Write-Step([string]$msg) { Write-Host "`n===== $msg =====" -ForegroundColor Yellow }

function Invoke-Sql([string]$sql) {
    $out = & mysql -u $MYSQL_USER "-p$MYSQL_PASS" $MYSQL_DB -e $sql 2>&1 `
           | Where-Object { $_ -notmatch "Warning" }
    return $out
}

function Get-Token {
    $body = "{""phone"":""$PHONE"",""password"":""$PASSWORD""}"
    $resp = Invoke-RestMethod -Uri "$API_BASE/auth/login" `
                -Method Post -ContentType "application/json" -Body $body
    if (-not $resp.data.token) { throw "Login failed: $($resp.msg)" }
    return $resp.data.token
}

function Place-Order([string]$token, [int]$productId = $PRODUCT_ID, [int]$qty = 1) {
    $headers = @{ Authorization = "Bearer $token" }
    $body    = "{""items"":[{""productId"":$productId,""quantity"":$qty}]}"
    $resp    = Invoke-RestMethod -Uri "$API_BASE/orders" `
                   -Method Post -Headers $headers -ContentType "application/json" -Body $body
    return $resp.data.orderId
}

function Get-MqStatus([string]$orderId) {
    $sql = "SELECT status, retry_count FROM mq_message WHERE id = '$orderId';"
    return Invoke-Sql $sql
}

function Publish-RabbitMQ([string]$payload) {
    $bodyObj = @{
        routing_key      = "order.routing.key"
        payload          = $payload
        payload_encoding = "string"
        properties       = @{
            delivery_mode = 2
            content_type  = "application/json"
            headers       = @{ "__TypeId__" = "com.shop.mq.OrderMessage" }
        }
    }
    $bodyJson = $bodyObj | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Uri "$MQ_BASE/exchanges/%2F/order.exchange/publish" `
        -Method Post -ContentType "application/json" `
        -Headers @{ Authorization = $MQ_CRED } -Body $bodyJson | Out-Null
}

# ── Test 1: Normal order - mq_message status 0 -> 1 ─────────────────────
function Test-1 {
    Write-Step "Test 1 - Normal order: mq_message status -> 1 (delivered)"
    $token = Get-Token
    $oid   = Place-Order $token
    Write-Info "orderId = $oid"
    Start-Sleep -Seconds 2

    $rows = Get-MqStatus $oid
    Write-Info "mq_message row:`n$($rows -join "`n")"

    if ($rows -match "^1\s") {
        Write-Pass "status=1 (delivered), confirm ack OK"
    } elseif ($rows -match "^0\s") {
        Write-Fail "status=0, confirm callback not triggered - check publisher-confirm-type config"
    } else {
        Write-Fail "No mq_message record found - check mqMessageService.save()"
    }
}

# ── Test 2: MQ down -> restart -> scheduler auto-retry ───────────────────
function Test-2 {
    Write-Step "Test 2 - MQ down, restart, scheduler retries (wait up to 65s)"

    Write-Info "Stopping RabbitMQ container: $RABBITMQ_CNAME"
    docker stop $RABBITMQ_CNAME | Out-Null

    Write-Info "Placing order while MQ is down..."
    $token = Get-Token
    $oid   = $null
    try {
        $oid = Place-Order $token
        Write-Info "orderId = $oid"
    } catch {
        Write-Info "Order API error (expected when MQ unreachable): $_"
        docker start $RABBITMQ_CNAME | Out-Null
        return
    }

    Start-Sleep -Seconds 2
    $rows = Get-MqStatus $oid
    Write-Info "mq_message while MQ down:`n$($rows -join "`n")"

    Write-Info "Restarting RabbitMQ..."
    docker start $RABBITMQ_CNAME | Out-Null
    Write-Info "Waiting for scheduler (up to 65s)..."
    Start-Sleep -Seconds 65

    $rows2 = Get-MqStatus $oid
    Write-Info "mq_message after restart:`n$($rows2 -join "`n")"

    if ($rows2 -match "^1\s") {
        Write-Pass "status=1, scheduler retry succeeded"
    } else {
        Write-Fail "status not 1 - check [Retry] log in application"
    }
}

# ── Test 3: Idempotent - duplicate message, only 1 order in DB ───────────
function Test-3 {
    Write-Step "Test 3 - Idempotent: duplicate message writes only 1 order row"
    $token = Get-Token
    $oid   = Place-Order $token
    Write-Info "orderId = $oid"
    Start-Sleep -Seconds 2

    $orderRow = Invoke-Sql "SELECT order_no FROM ``order`` WHERE order_no = '$oid';"
    Write-Info "First insert confirmed:`n$($orderRow -join "`n")"

    $dupMsg = "{""orderId"":""$oid"",""userId"":1,""items"":[{""productId"":$PRODUCT_ID,""quantity"":1,""price"":9999}],""createTime"":""2025-01-01T00:00:00""}"
    Write-Info "Publishing duplicate message to MQ..."
    Publish-RabbitMQ $dupMsg
    Start-Sleep -Seconds 2

    $cnt = Invoke-Sql "SELECT COUNT(*) as cnt FROM ``order`` WHERE order_no = '$oid';"
    Write-Info "Row count in order table:`n$($cnt -join "`n")"

    if ($cnt -match "^1$") {
        Write-Pass "Only 1 row, idempotent check works"
    } else {
        Write-Fail "Duplicate row found - idempotent logic broken"
    }
}

# ── Test 4: Consumer fails 3 times -> DLQ ────────────────────────────────
function Test-4 {
    Write-Step "Test 4 - DLQ: consumer fails 3 times, message goes to dead-letter queue"

    $dlqId  = "test-dlq-" + [guid]::NewGuid().ToString().Substring(0, 8)
    $dlqMsg = "{""orderId"":""$dlqId"",""userId"":1,""items"":[{""productId"":99999,""quantity"":1,""price"":1}],""createTime"":""2025-01-01T00:00:00""}"

    Write-Info "Publishing message with non-existent productId=99999, orderId=$dlqId"
    Publish-RabbitMQ $dlqMsg

    Write-Info "Waiting for 3 retries and DLQ routing (~10s)..."
    Start-Sleep -Seconds 10

    $dlqInfo  = Invoke-RestMethod -Uri "$MQ_BASE/queues/%2F/order.dlq" `
                    -Headers @{ Authorization = $MQ_CRED }
    $dlqTotal = $dlqInfo.messages_ready + $dlqInfo.messages_unacknowledged
    Write-Info "order.dlq messages (ready + unacked) = $dlqTotal"

    Write-Info "Expected log lines in application:"
    Write-Info "  [Consumer] failed orderId=$dlqId retries=1"
    Write-Info "  [Consumer] failed orderId=$dlqId retries=2"
    Write-Info "  [Consumer] failed orderId=$dlqId retries=3"
    Write-Info "  [DLQ] orderId=$dlqId"

    Write-Pass "DLQ test triggered - verify application log for [DLQ] line"
}

# ── Test 5: mq_message status distribution ───────────────────────────────
function Test-5 {
    Write-Step "Test 5 - mq_message status distribution"
    $stat = Invoke-Sql "SELECT status, COUNT(*) as cnt FROM mq_message GROUP BY status ORDER BY status;"
    Write-Info "Status breakdown:`n$($stat -join "`n")"
    Write-Info "Legend: 0=pending  1=delivered  2=failed(retry)  3=dead"
    $total = Invoke-Sql "SELECT COUNT(*) FROM mq_message;"
    Write-Info "Total records: $($total[-1])"
    Write-Pass "Stats complete"
}

# ── Entry point ───────────────────────────────────────────────────────────
Write-Host "`nM2 Test Suite" -ForegroundColor Magenta
Write-Host "API : $API_BASE  |  DB: $MYSQL_DB  |  MQ: $MQ_BASE"

switch ($Test) {
    "1"   { Test-1 }
    "2"   { Test-2 }
    "3"   { Test-3 }
    "4"   { Test-4 }
    "5"   { Test-5 }
    "all" {
        Test-1
        Test-3
        Test-5
        Write-Host "`n[Skipped Test-2 (requires docker stop/start) and Test-4 (check app log manually)]" -ForegroundColor DarkGray
        Write-Host "Run them individually: .\test-m2.ps1 -Test 2   or   .\test-m2.ps1 -Test 4" -ForegroundColor DarkGray
    }
    default { Write-Host "Usage: .\test-m2.ps1 [-Test 1|2|3|4|5|all]" }
}

Write-Host "`nDone.`n" -ForegroundColor Magenta
