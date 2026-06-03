# Admin backend API test script (PowerShell)
# Uses Invoke-RestMethod - no jq needed
# --------------------------------------------------------

$BASE = "http://localhost:8080/api"
$amp  = [char]38   # & -- avoids parse error with literal & in URLs

# ---- helpers ------------------------------------------------
function uGet($path, $tok, $qp = $null) {
    $h = @{}
    if ($tok) { $h["Authorization"] = "Bearer $tok" }
    $uri = "$BASE$path"
    if ($qp) {
        $qs = ($qp.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }) -join $amp
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

function ok($label, $r, $field = "code", $expect = 200) {
    $val = if ($field -eq "code") { $r.code } else { $r }
    if ($val -eq $expect) {
        Write-Host "[PASS] $label" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label  expect=$expect  got=$val" -ForegroundColor Red
    }
}

function expect4xx($label, $block, $expected = 400) {
    try {
        & $block
        Write-Host "[FAIL] $label  (no error thrown)" -ForegroundColor Red
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq $expected) {
            Write-Host "[PASS] $label  HTTP $code" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $label  expect=$expected  got=$code" -ForegroundColor Red
        }
    }
}

# =============================================================
# T1  Login + JWT role
# =============================================================
Write-Host "`n===== T1  Login =====" -ForegroundColor Yellow

$resp = uPost "/auth/login" $null '{"phone":"admin","password":"admin123"}'
ok "T1-1 login code=200" $resp
if ($resp.data.user.role -eq "ADMIN") {
    Write-Host "[PASS] T1-2 role=ADMIN" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T1-2 role expected=ADMIN got=$($resp.data.user.role)" -ForegroundColor Red
}
$AT = $resp.data.token
Write-Host "       ADMIN token: $($AT.Substring(0,20))..."

# Login as normal user -- change phone/password to a registered account
try {
    $ur = uPost "/auth/login" $null '{"phone":"13800000001","password":"123456"}'
    $UT = $ur.data.token
    Write-Host "       USER token ok"
} catch {
    $UT = ""
    Write-Host "[WARN] Normal user login failed -- T1-4 / T5 will be skipped" -ForegroundColor DarkYellow
}

# T1-3  unauthenticated -> 401
expect4xx "T1-3 no-token -> 401" { uGet "/admin/products" $null } 401

# T1-4  normal user -> 403
if ($UT) {
    expect4xx "T1-4 user-token -> 403" { uGet "/admin/products" $UT } 403
}

# =============================================================
# T2  Category management
# =============================================================
Write-Host "`n===== T2  Categories =====" -ForegroundColor Yellow

$r = uGet "/admin/categories" $AT
ok "T2-1 tree code=200" $r
$roots = $r.data | Where-Object { $null -eq $_.parentId }
if ($roots.Count -ge 3) {
    Write-Host "[PASS] T2-2 root count=$($roots.Count) >= 3" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T2-2 root count=$($roots.Count)" -ForegroundColor Red
}

$r = uPost "/admin/categories" $AT '{"name":"SmartWatch-test","parentId":1,"sort":3}'
ok "T2-3 create category" $r
$CID = $r.data.id
Write-Host "       new category id=$CID"

$r = uPut "/admin/categories/$CID" $AT '{"name":"SmartWatch-test2","parentId":1,"sort":5}'
ok "T2-4 update category" $r
if ($r.data.name -eq "SmartWatch-test2") {
    Write-Host "[PASS] T2-5 name updated" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T2-5 name=$($r.data.name)" -ForegroundColor Red
}

$r = uDelete "/admin/categories/$CID" $AT
ok "T2-6 delete category" $r

expect4xx "T2-7 empty name -> 400" {
    uPost "/admin/categories" $AT '{"name":""}'
}

# =============================================================
# T3  Brand management
# =============================================================
Write-Host "`n===== T3  Brands =====" -ForegroundColor Yellow

$r = uGet "/admin/brands/all" $AT
ok "T3-1 all brands code=200" $r
if ($r.data.Count -ge 5) {
    Write-Host "[PASS] T3-2 brand count=$($r.data.Count) >= 5" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T3-2 brand count=$($r.data.Count)" -ForegroundColor Red
}

$r = uGet "/admin/brands" $AT @{ page=1; size=10; keyword="Apple" }
ok "T3-3 brand page code=200" $r

$r = uPost "/admin/brands" $AT '{"name":"TestBrand","description":"test"}'
ok "T3-4 create brand" $r
$BID = $r.data.id
Write-Host "       new brand id=$BID"

$r = uPut "/admin/brands/$BID" $AT '{"name":"TestBrand2","description":"test2"}'
ok "T3-5 update brand" $r
if ($r.data.name -eq "TestBrand2") {
    Write-Host "[PASS] T3-6 brand name updated" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T3-6 brand name=$($r.data.name)" -ForegroundColor Red
}

$r = uDelete "/admin/brands/$BID" $AT
ok "T3-7 delete brand" $r

expect4xx "T3-8 empty name -> 400" { uPost "/admin/brands" $AT '{"name":""}' }

# =============================================================
# T4  Product management
# =============================================================
Write-Host "`n===== T4  Products =====" -ForegroundColor Yellow

# 4-1  paginated list
$r = uGet "/admin/products" $AT @{ page=1; size=10 }
ok "T4-1 list code=200" $r
Write-Host "       total=$($r.data.total)  count=$($r.data.list.Count)"

# 4-2  filter by category + brand
$r = uGet "/admin/products" $AT @{ categoryId=2; brandId=1 }
ok "T4-2 filter code=200" $r
$names = $r.data.list | ForEach-Object { $_.name }
if ($names -contains "iPhone 15 Pro") {
    Write-Host "[PASS] T4-3 iPhone 15 Pro in result" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-3 iPhone not found -- seed data may differ" -ForegroundColor DarkYellow
}

# 4-3  create draft (status=2, not in ES)
$r = uPost "/admin/products" $AT '{"name":"PSTestProduct","price":99.99,"stock":10,"categoryId":2,"brandId":2,"status":2}'
ok "T4-4 create product" $r
$PID = $r.data.id
if ($r.data.status -eq 2) {
    Write-Host "[PASS] T4-5 status=2 (draft)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T4-5 status=$($r.data.status)" -ForegroundColor Red
}

# 4-4  publish (status=1 -> sync ES)
$r = uPut "/admin/products/$PID/status?status=1" $AT
ok "T4-6 publish code=200" $r
if ($r.data.status -eq 1) {
    Write-Host "[PASS] T4-7 status=1 (on-sale)" -ForegroundColor Green
}

Start-Sleep -Seconds 1
$esR = uGet "/products" $null @{ keyword="PSTestProduct" }
if ($esR.data.total -gt 0) {
    Write-Host "[PASS] T4-8 product found in ES after publish" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-8 ES not found -- ES may not be running" -ForegroundColor DarkYellow
}

# 4-5  take offline (status=0 -> remove from ES)
$r = uPut "/admin/products/$PID/status?status=0" $AT
ok "T4-9 take offline code=200" $r

Start-Sleep -Seconds 1
$esR = uGet "/products" $null @{ keyword="PSTestProduct" }
if ($esR.data.total -eq 0) {
    Write-Host "[PASS] T4-10 not in ES after offline" -ForegroundColor Green
} else {
    Write-Host "[WARN] T4-10 still in ES (ES may have delay)" -ForegroundColor DarkYellow
}

# 4-6  soft delete
$r = uDelete "/admin/products/$PID" $AT
ok "T4-11 soft delete code=200" $r

$r = uGet "/admin/products" $AT @{ keyword="PSTestProduct" }
if ($r.data.total -eq 0) {
    Write-Host "[PASS] T4-12 not in list after delete" -ForegroundColor Green
} else {
    Write-Host "[FAIL] T4-12 still in list, total=$($r.data.total)" -ForegroundColor Red
}

# 4-7  validation
expect4xx "T4-13 missing name -> 400" {
    uPost "/admin/products" $AT '{"price":10}'
}

# =============================================================
# T5  Cart blocks offline products
# =============================================================
Write-Host "`n===== T5  Cart blocks offline product =====" -ForegroundColor Yellow

if (-not $UT) {
    Write-Host "[SKIP] no USER token" -ForegroundColor DarkYellow
} else {
    # take product 1 offline
    uPut "/admin/products/1/status?status=0" $AT | Out-Null

    expect4xx "T5-1 add offline product to cart -> 400" {
        $h = @{ Authorization = "Bearer $UT"; "Content-Type" = "application/json" }
        Invoke-RestMethod -Uri "$BASE/cart" -Method POST -Headers $h `
            -Body '{"productId":1,"quantity":1}'
    }

    # restore
    uPut "/admin/products/1/status?status=1" $AT | Out-Null
    Write-Host "       product 1 restored to on-sale"
}

# =============================================================
Write-Host "`n===== Done =====" -ForegroundColor Yellow
