# test-seckill.ps1
# 秒杀模块验收测试 — TC-SK-01 ~ TC-SK-07
# 用法：.\test-seckill.ps1

$BASE   = "http://localhost:8080"
$DBUSER = "root"
$DBPASS = "redhat"
$DBNAME = "shop_demo"
$pass = 0; $fail = 0; $skip = 0

function Pass($n)           { Write-Host "  [PASS] $n" -ForegroundColor Green;   $script:pass++ }
function Fail($n, $d = "")  { Write-Host "  [FAIL] $n  $d" -ForegroundColor Red; $script:fail++ }
function Skip($n, $r = "")  { Write-Host "  [SKIP] $n — $r" -ForegroundColor DarkGray; $script:skip++ }
function Assert($n, $c, $d = "") { if ($c) { Pass $n } else { Fail $n $d } }

function Db($sql) {
    $out = mysql -u $DBUSER -p$DBPASS $DBNAME --skip-column-names -e $sql 2>$null
    return ($out -join "`n").Trim()
}

function ApiPost($url, $body = $null, $token = $null) {
    $h = if ($token) { @{ Authorization = "Bearer $token" } } else { @{} }
    try {
        if ($body) { return Invoke-RestMethod -Method Post $url -Body $body -ContentType "application/json" -Headers $h }
        else        { return Invoke-RestMethod -Method Post $url -Headers $h }
    } catch { return $null }
}

function Register($phone) {
    ApiPost "$BASE/api/auth/register" (@{ phone=$phone; password="Sk@999888" } | ConvertTo-Json) | Out-Null
}

function GetToken($phone) {
    $r = ApiPost "$BASE/api/auth/login" (@{ phone=$phone; password="Sk@999888" } | ConvertTo-Json)
    return $r.data.token
}

function InitStock($pid) {
    ApiPost "$BASE/api/admin/seckill/init?productId=$pid" | Out-Null
}

function Seckill($pid, $tok) {
    try {
        $r = Invoke-RestMethod -Method Post "$BASE/api/seckill/$pid" -Headers @{ Authorization = "Bearer $tok" }
        return [int]$r.code
    } catch { return 500 }
}

# ============================================================
# SETUP：注册 20 个测试账号
# ============================================================
Write-Host "`n[SETUP] 注册 20 个测试账号..." -ForegroundColor Cyan
$tokens = @()
for ($i = 1; $i -le 20; $i++) {
    $phone = "185{0:D8}" -f $i          # 18500000001 ~ 18500000020
    Register $phone
    $tokens += GetToken $phone
}
$validCount = @($tokens | Where-Object { $_ }).Count
Write-Host "[SETUP] 有效 Token: $validCount / 20"
if ($validCount -lt 20) { Write-Host "[WARN] 部分账号登录失败，测试结果可能不准确" -ForegroundColor Yellow }

# ============================================================
Write-Host "`n--- TC-SK-01  数据库秒杀字段 ---" -ForegroundColor Yellow
# ============================================================
Assert "is_seckill 列存在"    ((Db "SHOW COLUMNS FROM product LIKE 'is_seckill'")    -match "is_seckill")
Assert "seckill_stock 列存在" ((Db "SHOW COLUMNS FROM product LIKE 'seckill_stock'") -match "seckill_stock")
Assert "seckill_price 列存在" ((Db "SHOW COLUMNS FROM product LIKE 'seckill_price'") -match "seckill_price")

$row = Db "SELECT CONCAT(is_seckill,',',seckill_stock,',',seckill_price) FROM product WHERE id=1"
Assert "id=1 is_seckill=1"       ($row -match "^1,")       "实际=$row"
Assert "id=1 seckill_stock=5"    ($row -match "^1,5,")     "实际=$row"
Assert "id=1 seckill_price=4999" ($row -match "4999")      "实际=$row"

# ============================================================
Write-Host "`n--- TC-SK-02  Redis 库存预热 ---" -ForegroundColor Yellow
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
$r = ApiPost "$BASE/api/admin/seckill/init?productId=1"
Assert "预热接口 code=200"                 ($r -and $r.code -eq 200)
Assert "预热后秒杀接口不返回库存不足(1005)" ((Seckill 1 $tokens[0]) -ne 1005)

# ============================================================
Write-Host "`n--- TC-SK-03  Lua 原子扣减 + 库存耗尽 ---" -ForegroundColor Yellow
# 库存=5，6 个不同用户顺序请求 → 5 成功，1 失败
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
InitStock 1

$r03 = @(); for ($i = 1; $i -le 6; $i++) { $r03 += Seckill 1 $tokens[$i] }
$s03 = @($r03 | Where-Object { $_ -eq 200  }).Count
$f03 = @($r03 | Where-Object { $_ -eq 1005 }).Count

Assert "成功数 = 5（库存精确消耗）"          ($s03 -eq 5)            "实际=$s03"
Assert "第 6 次返回 1005（库存不足）"         ($r03[5] -eq 1005)      "实际=$($r03[5])"
Assert "无其他异常状态（成功+库存不足=6）"    (($s03 + $f03) -eq 6)   "s=$s03 f=$f03"

# ============================================================
Write-Host "`n--- TC-SK-04  令牌桶限流（同用户连续 7 次）---" -ForegroundColor Yellow
# 库存设为 20（远大于桶容量），验证第 6+ 次被 429 拦截
# ============================================================
Db "UPDATE product SET seckill_stock=20 WHERE id=1" | Out-Null
InitStock 1

$r04 = @(); for ($j = 0; $j -lt 7; $j++) { $r04 += Seckill 1 $tokens[8] }
$cnt429    = @($r04       | Where-Object { $_ -eq 429 }).Count
$early429  = @($r04[0..4] | Where-Object { $_ -eq 429 }).Count   # 前 5 次不应有 429

Assert "7 次请求中出现 429 限流"           ($cnt429 -ge 1)      "429次数=$cnt429"
Assert "前 5 次请求均通过（桶容量=5）"     ($early429 -eq 0)    "前5次429=$early429"
Assert "第 6 或第 7 次命中 429"            ($r04[5] -eq 429 -or $r04[6] -eq 429) "codes=$($r04 -join ',')"

# ============================================================
Write-Host "`n--- TC-SK-05  并发 20 请求无超卖 ---" -ForegroundColor Yellow
# 20 个不同用户同时抢，库存=5；成功=5，DB 订单=5，无负库存
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
InitStock 1
Start-Sleep -Milliseconds 500   # 等令牌桶部分恢复

$before = [int]((Db 'SELECT COUNT(*) FROM `order`') -replace '\D','')

$jobs = for ($k = 0; $k -lt 20; $k++) {
    $tok = $tokens[$k]; $b = $BASE
    Start-Job -ScriptBlock {
        param($base, $tok)
        try {
            $r = Invoke-RestMethod -Method Post "$base/api/seckill/1" -Headers @{ Authorization = "Bearer $tok" }
            return [int]$r.code
        } catch { return 500 }
    } -ArgumentList $b, $tok
}
$c05 = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$cOk   = @($c05 | Where-Object { $_ -eq 200  }).Count
$c1005 = @($c05 | Where-Object { $_ -eq 1005 }).Count
$c429  = @($c05 | Where-Object { $_ -eq 429  }).Count

Assert "并发成功数 ≤ 5（未超卖）"     ($cOk -le 5)                     "成功=$cOk"
Assert "并发成功数 = 5（库存耗尽）"   ($cOk -eq 5)                     "成功=$cOk"
Assert "失败请求数 = 15"              (($c1005 + $c429) -eq 15)        "1005=$c1005 429=$c429"

Start-Sleep -Seconds 3   # 等异步落库完成
$after = [int]((Db 'SELECT COUNT(*) FROM `order`') -replace '\D','')
Assert "DB 新增订单数 = 5（异步落库一致）" (($after - $before) -eq 5) "新增=$($after-$before)"

# ============================================================
Write-Host "`n--- TC-SK-06  用户防重购（可选功能，未实现）---" -ForegroundColor Yellow
# ============================================================
# 需在 SeckillCacheService.deductStock 前执行：
#   redisTemplate.opsForValue().setIfAbsent("seckill:bought:{userId}:{productId}", "1", 1, TimeUnit.HOURS)
# 若 setIfAbsent 返回 false 则抛 BusinessException(1006, "每人限购一件")
Skip "同用户重复购买被拒(SETNX seckill:bought:{uid}:{pid})" "未实现"

# ============================================================
Write-Host "`n--- TC-SK-07  管理端库存回滚（可选功能，未实现）---" -ForegroundColor Yellow
# ============================================================
# 需新增接口 POST /api/admin/seckill/rollback?productId=&delta=
#   redisTemplate.opsForValue().increment(seckillStockKey(productId), delta)
Skip "DELETE 订单时 INCRBY 恢复 Redis 库存" "未实现"

# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null   # 恢复默认库存

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host " 通过: $pass" -ForegroundColor Green
Write-Host " 失败: $fail" -ForegroundColor $(if ($fail -gt 0){"Red"}else{"Green"})
Write-Host " 跳过: $skip" -ForegroundColor DarkGray
Write-Host "==============================`n"
