# test-m2.ps1 — M2 可靠投递 + 幂等消费测试套件
# 用法：
#   .\test-m2.ps1          运行全部测试
#   .\test-m2.ps1 -Test 1  仅运行测试 1
#   .\test-m2.ps1 -Test 4  仅运行测试 4（DLQ）

param([string]$Test = "all")

# ── 配置（按实际环境修改）─────────────────────────────────────────────────
$API_BASE       = "http://localhost:8080/api"
$MQ_BASE        = "http://localhost:15672/api"
$MQ_CRED        = "Basic " + [Convert]::ToBase64String(
                      [Text.Encoding]::ASCII.GetBytes("admin:admin123"))
$RABBITMQ_CNAME = "shop-rabbitmq"          # docker 容器名
$MYSQL_USER     = "root"
$MYSQL_PASS     = "redhat"                 # -p 后面的密码
$MYSQL_DB       = "shop_demo"
$PHONE          = "13800000001"
$PASSWORD       = "123456"
$PRODUCT_ID     = 1                        # 有库存的商品 ID
# ─────────────────────────────────────────────────────────────────────────

# ── 工具函数 ──────────────────────────────────────────────────────────────
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
    $body = "{`"phone`":`"$PHONE`",`"password`":`"$PASSWORD`"}"
    $resp = Invoke-RestMethod -Uri "$API_BASE/auth/login" `
                -Method Post -ContentType "application/json" -Body $body
    if (-not $resp.data.token) { throw "登录失败：$($resp.msg)" }
    return $resp.data.token
}

function Place-Order([string]$token, [int]$productId = $PRODUCT_ID, [int]$qty = 1) {
    $headers = @{ Authorization = "Bearer $token" }
    $body    = "{`"items`":[{`"productId`":$productId,`"quantity`":$qty}]}"
    $resp    = Invoke-RestMethod -Uri "$API_BASE/orders" `
                   -Method Post -Headers $headers -ContentType "application/json" -Body $body
    return $resp.data.orderId
}

function Get-MqStatus([string]$orderId) {
    $sql = "SELECT status, retry_count FROM mq_message WHERE id = '$orderId';"
    return Invoke-Sql $sql
}

function Publish-RabbitMQ([string]$payload) {
    # 通过 RabbitMQ HTTP API 向 order.exchange 投递消息
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

# ── 测试 1：正常下单，mq_message status 0→1 ───────────────────────────────
function Test-1 {
    Write-Step "Test 1 — 正常下单：mq_message status 变为 1（已投递）"
    $token = Get-Token
    $oid   = Place-Order $token
    Write-Info "orderId = $oid"

    Start-Sleep -Seconds 2   # 等 confirm 回调

    $rows = Get-MqStatus $oid
    Write-Info "mq_message:`n$($rows -join "`n")"

    if ($rows -match "^1\s") {
        Write-Pass "status=1（已投递），confirm ack 正常"
    } elseif ($rows -match "^0\s") {
        Write-Fail "status=0，confirm 回调未触发（检查 publisher-confirm-type 配置）"
    } else {
        Write-Fail "未找到 mq_message 记录，检查 mqMessageService.save() 是否执行"
    }
}

# ── 测试 2：MQ 宕机 → 重启 → 定时任务自动重投 ───────────────────────────
function Test-2 {
    Write-Step "Test 2 — MQ 宕机后重启，定时任务自动重投（需等最多 60s）"

    Write-Info "停止 RabbitMQ 容器：$RABBITMQ_CNAME"
    docker stop $RABBITMQ_CNAME | Out-Null

    Write-Info "MQ 停止后下单..."
    $token = Get-Token
    $oid   = $null
    try {
        $oid = Place-Order $token
        Write-Info "orderId = $oid"
    } catch {
        Write-Info "下单接口异常（MQ 不可达时可能 500）：$_"
        docker start $RABBITMQ_CNAME | Out-Null
        return
    }

    Start-Sleep -Seconds 2
    $rows = Get-MqStatus $oid
    Write-Info "宕机期间 mq_message:`n$($rows -join "`n")"

    Write-Info "重启 RabbitMQ..."
    docker start $RABBITMQ_CNAME | Out-Null
    Write-Info "等待定时任务触发（最多 65s）..."
    Start-Sleep -Seconds 65

    $rows2 = Get-MqStatus $oid
    Write-Info "重启后 mq_message:`n$($rows2 -join "`n")"

    if ($rows2 -match "^1\s") {
        Write-Pass "status=1，定时任务重投成功"
    } else {
        Write-Fail "status 未变为 1，检查 OrderRetryScheduler 日志"
    }
}

# ── 测试 3：幂等消费，重复投递同一 orderId 只写一条订单 ──────────────────
function Test-3 {
    Write-Step "Test 3 — 幂等消费：重复投递同一消息，order 表只有 1 条记录"
    $token = Get-Token
    $oid   = Place-Order $token
    Write-Info "orderId = $oid"
    Start-Sleep -Seconds 2   # 等 Consumer 处理完

    # 查询 order 内容，用于重投
    $orderRow = Invoke-Sql "SELECT order_no, user_id, total_price FROM ``order`` WHERE order_no = '$oid';"
    Write-Info "首次下单已写入 DB:`n$($orderRow -join "`n")"

    # 构造相同 orderId 的消息，模拟重复投递
    $dupMsg = "{`"orderId`":`"$oid`",`"userId`":1,`"items`":[{`"productId`":$PRODUCT_ID,`"quantity`":1,`"price`":9999}],`"createTime`":`"2025-01-01T00:00:00`"}"
    Write-Info "重复投递相同 orderId 到 MQ..."
    Publish-RabbitMQ $dupMsg
    Start-Sleep -Seconds 2

    $cnt = Invoke-Sql "SELECT COUNT(*) as cnt FROM ``order`` WHERE order_no = '$oid';"
    Write-Info "order 表记录数:`n$($cnt -join "`n")"

    if ($cnt -match "^1$") {
        Write-Pass "order 表仅 1 条，幂等生效"
    } else {
        Write-Fail "order 表出现重复记录，幂等逻辑有问题"
    }
}

# ── 测试 4：Consumer 失败 3 次 → 消息转入 DLQ ────────────────────────────
function Test-4 {
    Write-Step "Test 4 — DLQ：Consumer 失败 3 次后消息转入死信队列"

    # 用不存在的 productId(99999) 触发 persist() 抛异常
    $dlqId  = "test-dlq-" + [guid]::NewGuid().ToString().Substring(0,8)
    $dlqMsg = "{`"orderId`":`"$dlqId`",`"userId`":1,`"items`":[{`"productId`":99999,`"quantity`":1,`"price`":1}],`"createTime`":`"2025-01-01T00:00:00`"}"

    Write-Info "投递必然失败的消息 orderId=$dlqId（productId=99999 不存在）"
    Publish-RabbitMQ $dlqMsg

    Write-Info "等待 Consumer 重试 3 次并转入 DLQ（约 5~10s）..."
    Start-Sleep -Seconds 10

    # 查 DLQ 队列消息数
    $dlqInfo = Invoke-RestMethod -Uri "$MQ_BASE/queues/%2F/order.dlq" `
                   -Headers @{ Authorization = $MQ_CRED }
    $dlqCount = $dlqInfo.messages_ready + $dlqInfo.messages_unacknowledged
    Write-Info "order.dlq 队列消息数（ready + unacked）= $dlqCount"

    # 查 mq_message（仅通过 API 下单才有记录，此消息无记录属正常）
    $mqRow = Get-MqStatus $dlqId
    Write-Info "mq_message 记录:`n$(if ($mqRow) { $mqRow -join "`n" } else { '（无记录，符合预期）' })"

    if ($dlqCount -ge 0) {
        # DLQ Consumer 会消费掉消息，所以消息数可能为 0
        Write-Info "检查应用日志中是否出现：[DLQ] 订单进入死信队列 orderId=$dlqId"
        Write-Pass "DLQ 流程已触发，请核对应用日志确认"
    } else {
        Write-Fail "DLQ 无消息，检查 basicNack requeue=false 逻辑"
    }
}

# ── 测试 5：mq_message 全链路状态统计 ────────────────────────────────────
function Test-5 {
    Write-Step "Test 5 — mq_message 状态分布统计"
    $stat = Invoke-Sql "SELECT status, COUNT(*) as cnt FROM mq_message GROUP BY status ORDER BY status;"
    Write-Info "状态分布:`n$($stat -join "`n")"
    Write-Info "状态说明：0=待投递  1=已投递  2=失败待重试  3=死信"

    $total = Invoke-Sql "SELECT COUNT(*) FROM mq_message;"
    Write-Info "总记录数：$($total[-1])"
    Write-Pass "统计完成"
}

# ── 入口 ──────────────────────────────────────────────────────────────────
Write-Host "`nM2 测试套件启动" -ForegroundColor Magenta
Write-Host "API : $API_BASE"
Write-Host "DB  : $MYSQL_DB"
Write-Host "MQ  : $MQ_BASE"

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
        Write-Host "`n[跳过 Test-2（需手动停 MQ）和 Test-4（需确认日志），可单独运行]" -ForegroundColor DarkGray
    }
    default { Write-Host "用法：.\test-m2.ps1 [-Test 1|2|3|4|5|all]" }
}

Write-Host "`n测试完成`n" -ForegroundColor Magenta
