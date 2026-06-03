# Admin backend API test script (PowerShell)
# Run: .\docs\test_admin.ps1
# --------------------------------------------------------
# IMPORTANT: change $USER_PHONE / $USER_PASS to a registered normal user

$BASE       = "http://localhost:8080/api"
$amp        = [char]38        # & char -- avoids PS parse error in URL strings
$USER_PHONE = "13800000001"   # <-- change to your registered normal user
$USER_PASS  = "123456"

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
function uPut($path, $tok, $jsonBody = "{}") {
    $h = @{ "Content-Type" = "application/json" }
    if ($tok) { $h["Authorization"] = "Bearer $tok" }
    Invoke-RestMethod -Uri "$BASE$path" -Method PUT -Headers $h -Body $jsonBody
}
function uDelete($path, $tok) {
    $h = @{ "Authorization" = "Bearer $tok" }
    Invoke-RestMethod -Uri "$BASE$path" -Method DELETE -Headers $h
}

# ---- assertion helpers --------------------------------------
# For Spring Security errors: Invoke-RestMethod throws on HTTP 4xx
function expectHttp($label, $block, $expected) {
    try {
        $null = (& $block)   # $null= suppresses auto-print of return value
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

# For application errors: backend returns HTTP 200 + {code:4xx} in body
function expectAppErr($label, $r, $expected = 400) {
    if ($r.code -eq $expected) {
        Write-Host "[PASS] $label  code=$($r.code)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  expect=$expected  got=$($r.code)" -ForegroundColor Red
    }
}

function ok($label, $r) {
    if ($r.code -eq 200) {
        Write-Host "[PASS] $label" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  code=$($r.code)  msg=$($r.msg)" -ForegroundColor Red
    }
}

# =============================================================
# T1  Login + JWT role
# =============================================================
Write-Host "`n===== T1  Login =====" -ForegroundColor Yellow

$resp = uPost "/auth/login" $null '{"phone":"admin","password":"admin123"}'
ok "T1-1 admin login" $resp
if ($resp.data.user.role -eq "ADMIN") {
    Write-Host "[PASS] T1-2 role=ADMIN" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T1-2 role expected=ADMIN  got=$($resp.data.user.role)" -ForegroundColor Red
}
$AT = $resp.data.token
Write-Host "       ADMIN token: $($AT.Substring(0,20))..."

$UT = ""
try {
    $ur = uPost "/auth/login" $null "{`"phone`":`"$USER_PHONE`",`"password`":`"$USER_PASS`"}"
    $UT = $ur.data.token
    Write-Host "[PASS] T1-3 normal user login  role=$($ur.data.user.role)" -ForegroundColor Green
} catch {
    Write-Host "[WARN] T1-3 normal user login failed -- T1-5 / T5 skipped" -ForegroundColor DarkYellow
}

# T1-4  unauthenticated -> HTTP 401
expectHttp "T1-4 no-token -> 401" { uGet "/admin/products" $null } 401

# T1-5  authenticated as USER -> HTTP 403
if ($UT) {
    expectHttp "T1-5 user-token -> 403" { uGet "/admin/products" $UT } 403
}

# =============================================================
# T2  Category management
# =============================================================
Write-Host "`n===== T2  Categories =====" -ForegroundColor Yellow

$r = uGet "/admin/categories" $AT
ok "T2-1 get tree" $r
$roots = $r.data | Where-Object { $null -eq $_.parentId }
if ($roots.Count -ge 3) {
    Write-Host "[PASS] T2-2 root nodes=$($roots.Count) >= 3" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T2-2 root nodes=$($roots.Count)" -ForegroundColor Red
}

$r = uPost "/admin/categories" $AT '{"name":"SmartWatch-test","parentId":1,"sort":3}'
ok "T2-3 create category" $r
$CID = $r.data.id
Write-Host "       new id=$CID"

$r = uPut "/admin/categories/$CID" $AT '{"name":"SmartWatch-v2","parentId":1,"sort":5}'
ok "T2-4 update category" $r
if ($r.data.name -eq "SmartWatch-v2") {
    Write-Host "[PASS] T2-5 name updated" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T2-5 name=$($r.data.name)" -ForegroundColor Red
}

$r = uDelete "/admin/categories/$CID" $AT
ok "T2-6 delete category" $r

# T2-7  empty name -> app error code=400  (HTTP 200, body.code=400)
$r = uPost "/admin/categories" $AT '{"name":""}'
expectAppErr "T2-7 empty name -> code=400" $r

# =============================================================
# T3  Brand management
# =============================================================
Write-Host "`n===== T3  Brands =====" -ForegroundColor Yellow

$r = uGet "/admin/brands/all" $AT
ok "T3-1 all brands" $r
if ($r.data.Count -ge 5) {
    Write-Host "[PASS] T3-2 count=$($r.data.Count) >= 5" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T3-2 count=$($r.data.Count)" -ForegroundColor Red
}

$r = uGet "/admin/brands" $AT @{ page=1; size=10; keyword="Apple" }
ok "T3-3 brand page + keyword" $r

$r = uPost "/admin/brands" $AT '{"name":"TestBrand","description":"test"}'
ok "T3-4 create brand" $r
$BID = $r.data.id
Write-Host "       new id=$BID"

$r = uPut "/admin/brands/$BID" $AT '{"name":"TestBrand2","description":"test2"}'
ok "T3-5 update brand" $r
if ($r.data.name -eq "TestBrand2") {
    Write-Host "[PASS] T3-6 name updated" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T3-6 name=$($r.data.name)" -ForegroundColor Red
}

$r = uDelete "/admin/brands/$BID" $AT
ok "T3-7 delete brand" $r

# T3-8  empty name -> app error
$r = uPost "/admin/brands" $AT '{"name":""}'
expectAppErr "T3-8 empty name -> code=400" $r

# =============================================================
# T4  Product management   NOTE: $PID is reserved in PS (process id)
# =============================================================
Write-Host "`n===== T4  Products =====" -ForegroundColor Yellow

$r = uGet "/admin/products" $AT @{ page=1; size=10 }
ok "T4-1 list" $r
Write-Host "       total=$($r.data.total)  pageCount=$($r.data.list.Count)"

$r = uGet "/admin/products" $AT @{ categoryId=2; brandId=1 }
ok "T4-2 filter category+brand" $r
$names = $r.data.list | ForEach-Object { $_.name }
if ($names -contains "iPhone 15 Pro") {
    Write-Host "[PASS] T4-3 iPhone 15 Pro in filtered result" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-3 iPhone not found (seed data may differ)" -ForegroundColor DarkYellow
}

# T4-4  create draft (status=2, not in ES)
$r = uPost "/admin/products" $AT '{"name":"PSTestProduct","price":99.99,"stock":10,"categoryId":2,"brandId":2,"status":2}'
ok "T4-4 create product" $r
$PROD_ID = $r.data.id     # NOTE: use $PROD_ID, not $PID ($PID = PS process id, read-only)
if ($r.data.status -eq 2) {
    Write-Host "[PASS] T4-5 status=2 (draft)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T4-5 status=$($r.data.status)" -ForegroundColor Red
}
Write-Host "       new product id=$PROD_ID"

# T4-6  publish -> status=1, sync ES
$r = uPut "/admin/products/$PROD_ID/status?status=1" $AT
ok "T4-6 publish" $r
if ($r.data.status -eq 1) {
    Write-Host "[PASS] T4-7 status=1 (on-sale)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T4-7 status=$($r.data.status)" -ForegroundColor Red
}

Start-Sleep -Seconds 1
$esR = uGet "/products" $null @{ keyword="PSTestProduct" }
if ($esR.data.total -gt 0) {
    Write-Host "[PASS] T4-8 found in ES after publish" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-8 not in ES (ES may not be running)" -ForegroundColor DarkYellow
}

# T4-9  take offline -> status=0, remove from ES
$r = uPut "/admin/products/$PROD_ID/status?status=0" $AT
ok "T4-9 take offline" $r
if ($r.data.status -eq 0) {
    Write-Host "[PASS] T4-10 status=0 (offline)" -ForegroundColor Green
}

Start-Sleep -Seconds 1
$esR = uGet "/products" $null @{ keyword="PSTestProduct" }
if ($esR.data.total -eq 0) {
    Write-Host "[PASS] T4-11 not in ES after offline" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-11 still in ES (may have delay)" -ForegroundColor DarkYellow
}

# T4-12  soft delete
$r = uDelete "/admin/products/$PROD_ID" $AT
ok "T4-12 soft delete" $r

$r = uGet "/admin/products" $AT @{ keyword="PSTestProduct" }
if ($r.data.total -eq 0) {
    Write-Host "[PASS] T4-13 not in list after delete" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T4-13 still in list total=$($r.data.total)" -ForegroundColor Red
}

# T4-14  validation: missing name -> app error
$r = uPost "/admin/products" $AT '{"price":10}'
expectAppErr "T4-14 missing name -> code=400" $r

# =============================================================
# T5  Cart blocks offline product
# =============================================================
Write-Host "`n===== T5  Cart offline check =====" -ForegroundColor Yellow

if (-not $UT) {
    Write-Host "[SKIP] no USER token (set USER_PHONE/USER_PASS at top of script)" -ForegroundColor DarkYellow
} else {
    # take product 1 offline
    $null = uPut "/admin/products/1/status?status=0" $AT

    # normal user tries to add it to cart -> HTTP 200 + code=400
    $r = uPost "/cart" $UT '{"productId":1,"quantity":1}'
    expectAppErr "T5-1 add offline product -> code=400" $r
    Write-Host "       msg: $($r.msg)"

    # restore
    $null = uPut "/admin/products/1/status?status=1" $AT
    Write-Host "       product 1 restored to on-sale"
}

# =============================================================
Write-Host "`n===== Done =====" -ForegroundColor Yellow
