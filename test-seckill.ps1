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
    $a   = @("-u$DBUSER", "-p$DBPASS", $DBNAME, '-N', '-e', $sql)
    $raw = & mysql @a 2>$null
    $out = @($raw | Where-Object { $_ -and $_ -notmatch 'Warning' -and $_ -notmatch 'insecure' })
    return ($out -join "`n").Trim()
}

# Invoke POST; use inline JSON strings (avoid ConvertTo-Json encoding quirks)
function PostJson($url, $jsonBody, $token=$null) {
    $h = @{ 'Content-Type' = 'application/json; charset=utf-8' }
    if ($token) { $h['Authorization'] = "Bearer $token" }
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $url -Body $jsonBody `
                -Headers $h -UseBasicParsing -ErrorAction Stop
        return $resp.Content | ConvertFrom-Json
    } catch {
        return $null
    }
}

function InitStock($productId) {
    PostJson "$BASE/api/admin/seckill/init?productId=$productId" '' | Out-Null
}

function Seckill($productId, $tok) {
    try {
        $resp = Invoke-WebRequest -Method Post -Uri "$BASE/api/seckill/$productId" `
                -Headers @{ Authorization = "Bearer $tok" } -UseBasicParsing -ErrorAction Stop
        return [int]($resp.Content | ConvertFrom-Json).code
    } catch { return 500 }
}

function CountOrders() {
    $v = Db 'SELECT COUNT(*) FROM `order`'
    $n = $v -replace '\D', ''
    if ($n) { return [int]$n } else { return -1 }
}

# ============================================================
# SETUP
# ============================================================
Write-Host ''
Write-Host '[SETUP] DB connectivity...' -ForegroundColor Cyan
$dbTest  = Db 'SELECT 42'
$mysqlOk = ($dbTest -eq '42')
Write-Host "[SETUP] MySQL: $mysqlOk  (raw='$dbTest')"

# --- Auth diagnostic: register + login one account to verify the API works ---
Write-Host '[SETUP] Auth diagnostic...' -ForegroundColor Cyan
$diagPhone = '13900000777'
$diagJson  = '{"phone":"13900000777","password":"DiagPass99"}'
$regResp   = PostJson "$BASE/api/auth/register" $diagJson
$loginResp = PostJson "$BASE/api/auth/login"    $diagJson
Write-Host "[SETUP] Register: code=$($regResp.code)  msg=$($regResp.msg)"
Write-Host "[SETUP] Login:    code=$($loginResp.code)  hasToken=$(if ($loginResp.data.token) {'YES'} else {'NO - data=' + ($loginResp.data | ConvertTo-Json -Compress)})"

# Use epoch-derived suffix so phones are unique each test run
$phoneSuffix = '{0:D6}' -f ([int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) % 1000000)

Write-Host '[SETUP] Registering 20 test accounts...' -ForegroundColor Cyan
$tokens = @()
for ($i = 1; $i -le 20; $i++) {
    $ph   = '138' + $phoneSuffix + ('{0:D2}' -f $i)
    $json = '{"phone":"' + $ph + '","password":"SeckillTest1"}'
    PostJson "$BASE/api/auth/register" $json | Out-Null
    $lr   = PostJson "$BASE/api/auth/login" $json
    $tokens += $lr.data.token
}
$validCount = @($tokens | Where-Object { $_ }).Count
Write-Host "[SETUP] Valid tokens: $validCount / 20"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-01  DB seckill columns ---' -ForegroundColor Yellow
# ============================================================
if (-not $mysqlOk) {
    Skip 'DB column checks' 'MySQL not accessible'
} else {
    $c1 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='is_seckill'"
    $c2 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='seckill_stock'"
    $c3 = Db "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$DBNAME' AND table_name='product' AND column_name='seckill_price'"
    Assert 'col is_seckill exists'    ($c1 -eq '1') "count=$c1"
    Assert 'col seckill_stock exists' ($c2 -eq '1') "count=$c2"
    Assert 'col seckill_price exists' ($c3 -eq '1') "count=$c3"
    $v1 = Db 'SELECT is_seckill    FROM product WHERE id=1'
    $v2 = Db 'SELECT seckill_stock FROM product WHERE id=1'
    $v3 = Db 'SELECT seckill_price FROM product WHERE id=1'
    Assert 'id=1 is_seckill=1'       ($v1 -eq '1')        "val=$v1"
    Assert 'id=1 seckill_stock=5'    ($v2 -eq '5')        "val=$v2"
    Assert 'id=1 seckill_price=4999' ($v3 -match '4999')  "val=$v3"
}

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-02  Redis warm-up ---' -ForegroundColor Yellow
# ============================================================
if ($mysqlOk) { Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null }
$r2 = PostJson "$BASE/api/admin/seckill/init?productId=1" ''
Assert 'init returns code 200' ($r2 -and $r2.code -eq 200)
if ($validCount -gt 0) {
    $code2 = Seckill 1 $tokens[0]
    Assert 'after init seckill gets 200 or 1005' ($code2 -eq 200 -or $code2 -eq 1005)
} else { Skip 'after-init seckill check' 'no valid tokens' }

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-03  Lua atomic deduction ---' -ForegroundColor Yellow
# ============================================================
if ($mysqlOk) { Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null }
InitStock 1
$r03 = @()
for ($i = 1; $i -le 6; $i++) { $r03 += Seckill 1 $tokens[$i] }
$s03 = @($r03 | Where-Object { $_ -eq 200  }).Count
$f03 = @($r03 | Where-Object { $_ -eq 1005 }).Count
Assert 'success count is 5'        ($s03 -eq 5)        "actual=$s03"
Assert '6th request returns 1005'  ($r03[5] -eq 1005)  "actual=$($r03[5])"
Assert 'no unexpected codes'       (($s03+$f03) -eq 6)  "s=$s03 f=$f03"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-04  Token bucket rate limit ---' -ForegroundColor Yellow
# ============================================================
if ($mysqlOk) { Db 'UPDATE product SET seckill_stock=20 WHERE id=1' | Out-Null }
InitStock 1
$r04 = @()
for ($j = 0; $j -lt 7; $j++) { $r04 += Seckill 1 $tokens[8] }
$cnt429   = @($r04       | Where-Object { $_ -eq 429 }).Count
$early429 = @($r04[0..4] | Where-Object { $_ -eq 429 }).Count
Assert '429 appears in 7 requests'  ($cnt429 -ge 1)   "count=$cnt429"
Assert 'no 429 in first 5'          ($early429 -eq 0) "early429=$early429"
Assert 'request 6 or 7 hits 429'    ($r04[5] -eq 429 -or $r04[6] -eq 429) "codes=$($r04 -join ',')"

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-05  Concurrent 20 requests stock=5 no oversell ---' -ForegroundColor Yellow
# ============================================================
if ($mysqlOk) { Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null }
InitStock 1
Start-Sleep -Milliseconds 500
$before = CountOrders

$jobs = for ($k = 0; $k -lt 20; $k++) {
    $tok = $tokens[$k]; $b = $BASE
    Start-Job -ScriptBlock {
        param($base, $tok)
        try {
            $resp = Invoke-WebRequest -Method Post -Uri "$base/api/seckill/1" `
                    -Headers @{ Authorization = "Bearer $tok" } -UseBasicParsing -ErrorAction Stop
            return [int]($resp.Content | ConvertFrom-Json).code
        } catch { return 500 }
    } -ArgumentList $b, $tok
}
$c05  = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$cOk   = @($c05 | Where-Object { $_ -eq 200  }).Count
$c1005 = @($c05 | Where-Object { $_ -eq 1005 }).Count
$c429  = @($c05 | Where-Object { $_ -eq 429  }).Count

Assert 'success count not greater than 5' ($cOk -le 5)            "ok=$cOk"
Assert 'success count equals 5'           ($cOk -eq 5)            "ok=$cOk"
Assert 'fail count equals 15'             (($c1005+$c429) -eq 15) "1005=$c1005 429=$c429"

Start-Sleep -Seconds 3
$after = CountOrders
if ($before -ge 0 -and $after -ge 0) {
    Assert 'DB new orders equals 5' (($after-$before) -eq 5) "delta=$($after-$before)"
} else { Skip 'DB order count' 'MySQL not accessible' }

# ============================================================
Write-Host ''
Write-Host '--- TC-SK-06  Per-user dedup  optional not implemented ---' -ForegroundColor Yellow
Skip 'SETNX seckill:bought check' 'not implemented'
Write-Host ''
Write-Host '--- TC-SK-07  Rollback stock  optional not implemented ---' -ForegroundColor Yellow
Skip 'INCRBY rollback endpoint' 'not implemented'

# ============================================================
if ($mysqlOk) { Db 'UPDATE product SET seckill_stock=5 WHERE id=1' | Out-Null }

Write-Host ''
Write-Host '==============================' -ForegroundColor Cyan
Write-Host " pass: $pass" -ForegroundColor Green
Write-Host " fail: $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
Write-Host " skip: $skip" -ForegroundColor DarkGray
Write-Host '=============================='
Write-Host ''
