# test-seckill.ps1  --  Seckill module acceptance tests TC-SK-01 ~ TC-SK-07

$BASE   = 'http://localhost:8080'
$DBUSER = 'root'
$DBPASS = 'redhat'
$DBNAME = 'shop_demo'
$pass = 0; $fail = 0; $skip = 0

function Pass($n)         { Write-Host "  [PASS] $n" -ForegroundColor Green;   $script:pass++ }
function Fail($n, $d='')  { Write-Host "  [FAIL] $n  $d" -ForegroundColor Red; $script:fail++ }
function Skip($n, $r='')  { Write-Host "  [SKIP] $n -- $r" -ForegroundColor DarkGray; $script:skip++ }
function Assert($n, $c, $d='') { if ($c) { Pass $n } else { Fail $n $d } }

function Db($sql) {
    $out = mysql -u $DBUSER -p$DBPASS $DBNAME -N -e $sql 2>$null
    return ($out -join "`n").Trim()
}

function ApiPost($url, $body=$null, $token=$null) {
    $h = if ($token) { @{ Authorization = "Bearer $token" } } else { @{} }
    try {
        if ($body) {
            return Invoke-RestMethod -Method Post $url -Body $body `
                   -ContentType 'application/json' -Headers $h -ErrorAction Stop
        } else {
            return Invoke-RestMethod -Method Post $url -Headers $h -ErrorAction Stop
        }
    } catch { return $null }
}

function Register($phone) {
    $b = @{ phone = $phone; password = 'Test123456' } | ConvertTo-Json
    ApiPost "$BASE/api/auth/register" $b | Out-Null
}

function GetToken($phone) {
    $b = @{ phone = $phone; password = 'Test123456' } | ConvertTo-Json
    $r = ApiPost "$BASE/api/auth/login" $b
    return $r.data.token
}

# $productId avoids collision with the read-only $pid automatic variable
function InitStock($productId) {
    ApiPost "$BASE/api/admin/seckill/init?productId=$productId" | Out-Null
}

function Seckill($productId, $tok) {
    try {
        $r = Invoke-RestMethod -Method Post "$BASE/api/seckill/$productId" `
             -Headers @{ Authorization = "Bearer $tok" } -ErrorAction Stop
        return [int]$r.code
    } catch { return 500 }
}

function CountOrders() {
    $v = Db 'SELECT COUNT(*) FROM `order`'
    $n = $v -replace '\D', ''
    if ($n) { return [int]$n } else { return 0 }
}

# ============================================================
# SETUP: register 20 test accounts
# ============================================================
Write-Host ''
Write-Host '[SETUP] Registering 20 test accounts...' -ForegroundColor Cyan
$tokens = @()
for ($i = 1; $i -le 20; $i++) {
    $phone = '185' + ('{0:D8}' -f $i)
    Register $phone
    $tokens += GetToken $phone
}
$validCount = @($tokens | Where-Object { $_ }).Count
Write-Host "[SETUP] Valid tokens: $validCount / 20"
if ($validCount -eq 0) {
    Write-Host '[SETUP] ERROR: no tokens - check backend is running at http://localhost:8080' -ForegroundColor Red
}

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-01  DB seckill columns ---' -ForegroundColor Yellow
# ============================================================
$chk1 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='is_seckill'"
$chk2 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='seckill_stock'"
$chk3 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='seckill_price'"
Assert 'col is_seckill exists'    ($chk1 -eq '1')  "count=$chk1"
Assert 'col seckill_stock exists' ($chk2 -eq '1')  "count=$chk2"
Assert 'col seckill_price exists' ($chk3 -eq '1')  "count=$chk3"

$isSeckill    = Db 'SELECT is_seckill    FROM product WHERE id=1'
$seckillStock = Db 'SELECT seckill_stock FROM product WHERE id=1'
$seckillPrice = Db 'SELECT seckill_price FROM product WHERE id=1'
Assert 'id=1 is_seckill=1'       ($isSeckill    -eq '1')     "val=$isSeckill"
Assert 'id=1 seckill_stock=5'    ($seckillStock -eq '5')     "val=$seckillStock"
Assert 'id=1 seckill_price=4999' ($seckillPrice -match '4999') "val=$seckillPrice"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-02  Redis warm-up ---' -ForegroundColor Yellow
# ============================================================
Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null
$r2 = ApiPost "$BASE/api/admin/seckill/init?productId=1"
Assert 'init returns code 200'            ($r2 -and $r2.code -eq 200)
Assert 'after init seckill not code 1005' ((Seckill 1 $tokens[0]) -ne 1005)

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-03  Lua atomic deduction ---' -ForegroundColor Yellow
# stock=5, 6 different users sequential: first 5 ok, 6th returns 1005
# ============================================================
Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null
InitStock 1
$r03 = @()
for ($i = 1; $i -le 6; $i++) { $r03 += Seckill 1 $tokens[$i] }
$s03 = @($r03 | Where-Object { $_ -eq 200  }).Count
$f03 = @($r03 | Where-Object { $_ -eq 1005 }).Count
Assert 'success count is 5'          ($s03 -eq 5)          "actual=$s03"
Assert '6th request returns 1005'    ($r03[5] -eq 1005)    "actual=$($r03[5])"
Assert 'no unexpected status code'   (($s03+$f03) -eq 6)   "s=$s03 f=$f03"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-04  Token bucket rate limit ---' -ForegroundColor Yellow
# stock=20 (far above bucket cap), same user 7 rapid requests
# first 5 pass, request 6+ returns 429
# ============================================================
Db 'UPDATE product SET seckill_stock=20 WHERE id=1' | Out-Null
InitStock 1
$r04 = @()
for ($j = 0; $j -lt 7; $j++) { $r04 += Seckill 1 $tokens[8] }
$cnt429   = @($r04       | Where-Object { $_ -eq 429 }).Count
$early429 = @($r04[0..4] | Where-Object { $_ -eq 429 }).Count
Assert '429 appears in 7 requests'     ($cnt429 -ge 1)   "count=$cnt429"
Assert 'no 429 in first 5 requests'    ($early429 -eq 0) "early429=$early429"
Assert 'request 6 or 7 hits 429'       ($r04[5] -eq 429 -or $r04[6] -eq 429) "codes=$($r04 -join ',')"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-05  Concurrent 20 requests stock=5 no oversell ---' -ForegroundColor Yellow
# ============================================================
Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null
InitStock 1
Start-Sleep -Milliseconds 500

$before = CountOrders

$jobs = for ($k = 0; $k -lt 20; $k++) {
    $tok = $tokens[$k]
    $b   = $BASE
    Start-Job -ScriptBlock {
        param($base, $tok)
        try {
            $r = Invoke-RestMethod -Method Post "$base/api/seckill/1" `
                 -Headers @{ Authorization = "Bearer $tok" } -ErrorAction Stop
            return [int]$r.code
        } catch { return 500 }
    } -ArgumentList $b, $tok
}
$c05  = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$cOk   = @($c05 | Where-Object { $_ -eq 200  }).Count
$c1005 = @($c05 | Where-Object { $_ -eq 1005 }).Count
$c429  = @($c05 | Where-Object { $_ -eq 429  }).Count

Assert 'success count not greater than 5'  ($cOk -le 5)              "ok=$cOk"
Assert 'success count equals 5'            ($cOk -eq 5)              "ok=$cOk"
Assert 'fail count equals 15'              (($c1005+$c429) -eq 15)   "1005=$c1005 429=$c429"

Start-Sleep -Seconds 3
$after = CountOrders
$delta = $after - $before
Assert 'DB new orders equals 5'            ($delta -eq 5)            "delta=$delta"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-06  Per-user dedup buy  optional not implemented ---' -ForegroundColor Yellow
# ============================================================
Skip 'SETNX seckill:bought check' 'not implemented'

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-07  Admin rollback stock  optional not implemented ---' -ForegroundColor Yellow
# ============================================================
Skip 'INCRBY rollback endpoint' 'not implemented'

# ============================================================
Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null

Write-Host ''
Write-Host '==============================' -ForegroundColor Cyan
Write-Host " pass: $pass" -ForegroundColor Green
Write-Host " fail: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
Write-Host " skip: $skip" -ForegroundColor DarkGray
Write-Host '=============================='
Write-Host ''
