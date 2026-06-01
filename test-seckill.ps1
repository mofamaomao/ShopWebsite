# test-seckill.ps1  --  Seckill module acceptance tests TC-SK-01 ~ TC-SK-07

$BASE   = "http://localhost:8080"
$DBUSER = "root"
$DBPASS = "redhat"
$DBNAME = "shop_demo"
$pass = 0; $fail = 0; $skip = 0

function Pass($n)          { Write-Host "  [PASS] $n" -ForegroundColor Green;   $script:pass++ }
function Fail($n, $d="")   { Write-Host "  [FAIL] $n  $d" -ForegroundColor Red; $script:fail++ }
function Skip($n, $r="")   { Write-Host "  [SKIP] $n -- $r" -ForegroundColor DarkGray; $script:skip++ }
function Assert($n, $c, $d="") { if ($c) { Pass $n } else { Fail $n $d } }

function Db($sql) {
    $out = mysql -u $DBUSER -p$DBPASS $DBNAME --skip-column-names -e $sql 2>$null
    return ($out -join "`n").Trim()
}

function ApiPost($url, $body=$null, $token=$null) {
    $h = if ($token) { @{ Authorization = "Bearer $token" } } else { @{} }
    try {
        if ($body) { return Invoke-RestMethod -Method Post $url -Body $body -ContentType "application/json" -Headers $h }
        else        { return Invoke-RestMethod -Method Post $url -Headers $h }
    } catch { return $null }
}

function Register($phone) {
    $b = '{"phone":"' + $phone + '","password":"Sk@999888"}'
    ApiPost "$BASE/api/auth/register" $b | Out-Null
}

function GetToken($phone) {
    $b = '{"phone":"' + $phone + '","password":"Sk@999888"}'
    $r = ApiPost "$BASE/api/auth/login" $b
    return $r.data.token
}

function InitStock($pid) { ApiPost "$BASE/api/admin/seckill/init?productId=$pid" | Out-Null }

function Seckill($pid, $tok) {
    try {
        $r = Invoke-RestMethod -Method Post "$BASE/api/seckill/$pid" `
             -Headers @{ Authorization = "Bearer $tok" }
        return [int]$r.code
    } catch { return 500 }
}

# ============================================================
# SETUP: register 20 test accounts
# ============================================================
Write-Host "`n[SETUP] Registering 20 test accounts..." -ForegroundColor Cyan
$tokens = @()
for ($i = 1; $i -le 20; $i++) {
    $phone = "185{0:D8}" -f $i
    Register $phone
    $tokens += GetToken $phone
}
$valid = @($tokens | Where-Object { $_ }).Count
Write-Host "[SETUP] Valid tokens: $valid / 20"

# ============================================================
Write-Host "`n--- TC-SK-01  DB seckill columns ---" -ForegroundColor Yellow
# ============================================================
Assert "column is_seckill exists"    ((Db "SHOW COLUMNS FROM product LIKE 'is_seckill'")    -match "is_seckill")
Assert "column seckill_stock exists" ((Db "SHOW COLUMNS FROM product LIKE 'seckill_stock'") -match "seckill_stock")
Assert "column seckill_price exists" ((Db "SHOW COLUMNS FROM product LIKE 'seckill_price'") -match "seckill_price")

$row = Db "SELECT CONCAT(is_seckill,'-',seckill_stock,'-',seckill_price) FROM product WHERE id=1"
Assert "id=1  is_seckill=1"       ($row -match "^1-")      "row=$row"
Assert "id=1  seckill_stock=5"    ($row -match "^1-5-")    "row=$row"
Assert "id=1  seckill_price=4999" ($row -match "4999")     "row=$row"

# ============================================================
Write-Host "`n--- TC-SK-02  Redis warm-up ---" -ForegroundColor Yellow
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
$r2 = ApiPost "$BASE/api/admin/seckill/init?productId=1"
Assert "init returns code=200"             ($r2 -and $r2.code -eq 200)
Assert "after init seckill not code=1005"  ((Seckill 1 $tokens[0]) -ne 1005)

# ============================================================
Write-Host "`n--- TC-SK-03  Lua atomic deduction ---" -ForegroundColor Yellow
# stock=5, 6 different users sequential => 5 ok, 1 fail(1005)
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
InitStock 1
$r03 = @()
for ($i = 1; $i -le 6; $i++) { $r03 += Seckill 1 $tokens[$i] }
$s03 = @($r03 | Where-Object { $_ -eq 200  }).Count
$f03 = @($r03 | Where-Object { $_ -eq 1005 }).Count
Assert "success count = 5"                ($s03 -eq 5)           "actual=$s03"
Assert "6th request returns 1005"         ($r03[5] -eq 1005)     "actual=$($r03[5])"
Assert "no unexpected status (ok+1005=6)" (($s03+$f03) -eq 6)    "s=$s03 f=$f03"

# ============================================================
Write-Host "`n--- TC-SK-04  Token bucket rate limit ---" -ForegroundColor Yellow
# stock=20 (> bucket capacity), same user 7 rapid requests
# => first 5 pass, 6th+ returns 429
# ============================================================
Db "UPDATE product SET seckill_stock=20 WHERE id=1" | Out-Null
InitStock 1
$r04 = @()
for ($j = 0; $j -lt 7; $j++) { $r04 += Seckill 1 $tokens[8] }
$cnt429   = @($r04       | Where-Object { $_ -eq 429 }).Count
$early429 = @($r04[0..4] | Where-Object { $_ -eq 429 }).Count
Assert "429 appears in 7 requests"           ($cnt429 -ge 1)    "429 count=$cnt429"
Assert "no 429 in first 5 (bucket cap=5)"    ($early429 -eq 0)  "early 429=$early429"
Assert "request 6 or 7 hits 429"             ($r04[5] -eq 429 -or $r04[6] -eq 429) "codes=$($r04 -join ',')"

# ============================================================
Write-Host "`n--- TC-SK-05  Concurrent 20 requests, stock=5, no oversell ---" -ForegroundColor Yellow
# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null
InitStock 1
Start-Sleep -Milliseconds 500

$before = [int]((Db "SELECT COUNT(*) FROM \`order\`") -replace '\D','')

$jobs = for ($k = 0; $k -lt 20; $k++) {
    $tok = $tokens[$k]; $b = $BASE
    Start-Job -ScriptBlock {
        param($base, $tok)
        try {
            $r = Invoke-RestMethod -Method Post "$base/api/seckill/1" `
                 -Headers @{ Authorization = "Bearer $tok" }
            return [int]$r.code
        } catch { return 500 }
    } -ArgumentList $b, $tok
}
$c05  = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$cOk   = @($c05 | Where-Object { $_ -eq 200  }).Count
$c1005 = @($c05 | Where-Object { $_ -eq 1005 }).Count
$c429  = @($c05 | Where-Object { $_ -eq 429  }).Count

Assert "success count <= 5  (no oversell)"    ($cOk -le 5)                  "ok=$cOk"
Assert "success count = 5   (stock sold out)"  ($cOk -eq 5)                  "ok=$cOk"
Assert "fail count = 15     (1005 or 429)"     (($c1005+$c429) -eq 15)       "1005=$c1005 429=$c429"

Start-Sleep -Seconds 3
$after = [int]((Db "SELECT COUNT(*) FROM \`order\`") -replace '\D','')
Assert "DB new orders = 5   (async write ok)"  (($after-$before) -eq 5)      "delta=$($after-$before)"

# ============================================================
Write-Host "`n--- TC-SK-06  Per-user dedup buy (optional, not implemented) ---" -ForegroundColor Yellow
# ============================================================
# Required: before deductStock, call
#   redisTemplate.opsForValue().setIfAbsent("seckill:bought:{uid}:{pid}", "1", 1h)
# if false => throw BusinessException(1006, "One item per user")
Skip "SETNX seckill:bought check" "not implemented yet"

# ============================================================
Write-Host "`n--- TC-SK-07  Admin rollback stock (optional, not implemented) ---" -ForegroundColor Yellow
# ============================================================
# Required: POST /api/admin/seckill/rollback?productId=&delta=
#   redisTemplate.opsForValue().increment(seckillStockKey(productId), delta)
Skip "INCRBY rollback endpoint" "not implemented yet"

# ============================================================
Db "UPDATE product SET seckill_stock=5 WHERE id=1" | Out-Null

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host " pass: $pass" -ForegroundColor Green
Write-Host " fail: $fail" -ForegroundColor $(if ($fail -gt 0){"Red"}else{"Green"})
Write-Host " skip: $skip" -ForegroundColor DarkGray
Write-Host "==============================`n"
