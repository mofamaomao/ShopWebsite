# ============================================================
# 管理后台接口测试脚本（PowerShell）
# 使用 Invoke-RestMethod，自动解析 JSON，无需 jq
# ============================================================

$BASE = "http://localhost:8080/api"

function Print-Result($label, $resp) {
    Write-Host "`n[$label]" -ForegroundColor Cyan
    $resp | ConvertTo-Json -Depth 10 | Write-Host
}

function Assert-Equal($label, $actual, $expected) {
    if ($actual -eq $expected) {
        Write-Host "[PASS] $label : $actual" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label : expected=$expected, actual=$actual" -ForegroundColor Red
    }
}

# ── T1 管理员登录 ────────────────────────────────────────────
Write-Host "`n===== T1 管理员登录 =====" -ForegroundColor Yellow

$resp = Invoke-RestMethod -Uri "$BASE/auth/login" -Method POST `
    -ContentType "application/json" `
    -Body '{"phone":"admin","password":"admin123"}'

Print-Result "登录响应" $resp
Assert-Equal "登录code=200"      $resp.code 200
Assert-Equal "role=ADMIN"        $resp.data.user.role "ADMIN"

$ADMIN_TOKEN = $resp.data.token
Write-Host "ADMIN_TOKEN 已保存：$($ADMIN_TOKEN.Substring(0,20))..." -ForegroundColor DarkGray

# 注意：请先注册一个普通用户，或将下面账号改为你已注册的账号
$userResp = Invoke-RestMethod -Uri "$BASE/auth/login" -Method POST `
    -ContentType "application/json" `
    -Body '{"phone":"13800000001","password":"123456"}'
$USER_TOKEN = $userResp.data.token
Write-Host "USER_TOKEN 已保存"

$adminHeader = @{ Authorization = "Bearer $ADMIN_TOKEN" }
$userHeader  = @{ Authorization = "Bearer $USER_TOKEN" }

# ── T1.2 权限校验 ────────────────────────────────────────────
Write-Host "`n----- T1.2 权限校验 -----"

# 管理员可访问 → code=200
$r = Invoke-RestMethod -Uri "$BASE/admin/products" -Headers $adminHeader
Assert-Equal "管理员访问code=200" $r.code 200

# 未登录 → 401
try {
    Invoke-RestMethod -Uri "$BASE/admin/products"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert-Equal "未登录访问=401" $code 401
}

# 普通用户 → 403
try {
    Invoke-RestMethod -Uri "$BASE/admin/products" -Headers $userHeader
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert-Equal "普通用户访问=403" $code 403
}

# ── T2 分类管理 ──────────────────────────────────────────────
Write-Host "`n===== T2 分类管理 =====" -ForegroundColor Yellow

# 2.1 获取分类树
$r = Invoke-RestMethod -Uri "$BASE/admin/categories" -Headers $adminHeader
Assert-Equal "分类树code=200" $r.code 200
$rootCount = ($r.data | Where-Object { $null -eq $_.parentId }).Count
Assert-Equal "一级分类数量>=3" ($rootCount -ge 3) $true
Write-Host "分类树一级数量：$rootCount"

# 2.2 新增子分类
$r = Invoke-RestMethod -Uri "$BASE/admin/categories" -Method POST `
    -Headers $adminHeader -ContentType "application/json" `
    -Body '{"name":"智能手表","parentId":1,"sort":3}'
Assert-Equal "新增分类code=200" $r.code 200
$NEW_CAT_ID = $r.data.id
Write-Host "新增分类ID：$NEW_CAT_ID"

# 2.3 编辑分类
$r = Invoke-RestMethod -Uri "$BASE/admin/categories/$NEW_CAT_ID" -Method PUT `
    -Headers $adminHeader -ContentType "application/json" `
    -Body '{"name":"智能手表Pro","parentId":1,"sort":5}'
Assert-Equal "编辑分类code=200" $r.code 200
Assert-Equal "名称已更新" $r.data.name "智能手表Pro"

# 2.4 删除分类
$r = Invoke-RestMethod -Uri "$BASE/admin/categories/$NEW_CAT_ID" -Method DELETE `
    -Headers $adminHeader
Assert-Equal "删除分类code=200" $r.code 200

# 2.5 必填项校验
try {
    Invoke-RestMethod -Uri "$BASE/admin/categories" -Method POST `
        -Headers $adminHeader -ContentType "application/json" `
        -Body '{"name":""}'
    Write-Host "[FAIL] 空name应返回400" -ForegroundColor Red
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert-Equal "空name=400" $code 400
}

# ── T3 品牌管理 ──────────────────────────────────────────────
Write-Host "`n===== T3 品牌管理 =====" -ForegroundColor Yellow

# 3.1 全量品牌
$r = Invoke-RestMethod -Uri "$BASE/admin/brands/all" -Headers $adminHeader
Assert-Equal "全量品牌code=200" $r.code 200
Assert-Equal "品牌数量>=5" ($r.data.Count -ge 5) $true
Write-Host "品牌数量：$($r.data.Count)"

# 3.2 分页查询+关键词
$r = Invoke-RestMethod -Uri "$BASE/admin/brands?page=1&size=10&keyword=%E8%8B%B9" -Headers $adminHeader
Assert-Equal "品牌分页code=200" $r.code 200

# 3.3 新增品牌
$r = Invoke-RestMethod -Uri "$BASE/admin/brands" -Method POST `
    -Headers $adminHeader -ContentType "application/json" `
    -Body '{"name":"三星","description":"韩国电子巨头"}'
Assert-Equal "新增品牌code=200" $r.code 200
$BRAND_ID = $r.data.id
Write-Host "新增品牌ID：$BRAND_ID"

# 3.4 更新品牌
$r = Invoke-RestMethod -Uri "$BASE/admin/brands/$BRAND_ID" -Method PUT `
    -Headers $adminHeader -ContentType "application/json" `
    -Body '{"name":"三星 Samsung","description":"韩国电子巨头"}'
Assert-Equal "更新品牌code=200" $r.code 200
Assert-Equal "品牌名更新" $r.data.name "三星 Samsung"

# 3.5 删除品牌
$r = Invoke-RestMethod -Uri "$BASE/admin/brands/$BRAND_ID" -Method DELETE `
    -Headers $adminHeader
Assert-Equal "删除品牌code=200" $r.code 200

# ── T4 商品管理 ──────────────────────────────────────────────
Write-Host "`n===== T4 商品管理 =====" -ForegroundColor Yellow

# 4.1 分页查询（无过滤）
$r = Invoke-RestMethod -Uri "$BASE/admin/products?page=1&size=10" -Headers $adminHeader
Assert-Equal "商品分页code=200" $r.code 200
Assert-Equal "有商品数据" ($r.data.list.Count -gt 0) $true
Write-Host "商品总数：$($r.data.total)"

# 4.2 多条件过滤
$r = Invoke-RestMethod -Uri "$BASE/admin/products?categoryId=2&brandId=1" -Headers $adminHeader
$names = $r.data.list | ForEach-Object { $_.name }
Write-Host "分类2+品牌1的商品：$($names -join ', ')"
Assert-Equal "iPhone在列表中" ($names -contains "iPhone 15 Pro") $true

# 4.3 新增商品（草稿，status=2，不进ES）
$body = '{"name":"PowerShell测试商品","price":99.99,"stock":50,"categoryId":2,"brandId":2,"description":"测试用","status":2}'
$r = Invoke-RestMethod -Uri "$BASE/admin/products" -Method POST `
    -Headers $adminHeader -ContentType "application/json" -Body $body
Assert-Equal "新增商品code=200" $r.code 200
$PROD_ID = $r.data.id
Write-Host "新增商品ID：$PROD_ID，状态：$($r.data.status)"
Assert-Equal "草稿状态=2" $r.data.status 2

# 4.4 上架商品（status=1 → ES同步）
$r = Invoke-RestMethod -Uri "$BASE/admin/products/$PROD_ID/status?status=1" `
    -Method PUT -Headers $adminHeader
Assert-Equal "上架code=200" $r.code 200
Assert-Equal "上架status=1" $r.data.status 1

# 验证ES能搜到（等1秒让ES索引生效）
Start-Sleep -Seconds 1
$r = Invoke-RestMethod -Uri "$BASE/products?keyword=PowerShell%E6%B5%8B%E8%AF%95%E5%95%86%E5%93%81"
$found = $r.data.products.Count -gt 0
Assert-Equal "上架后ES可搜到" $found $true

# 4.5 下架商品（status=0 → ES删除）
$r = Invoke-RestMethod -Uri "$BASE/admin/products/$PROD_ID/status?status=0" `
    -Method PUT -Headers $adminHeader
Assert-Equal "下架code=200" $r.code 200
Assert-Equal "下架status=0" $r.data.status 0

Start-Sleep -Seconds 1
$r = Invoke-RestMethod -Uri "$BASE/products?keyword=PowerShell%E6%B5%8B%E8%AF%95%E5%95%86%E5%93%81"
Assert-Equal "下架后ES搜不到" $r.data.total 0

# 4.6 软删除
$r = Invoke-RestMethod -Uri "$BASE/admin/products/$PROD_ID" -Method DELETE `
    -Headers $adminHeader
Assert-Equal "软删除code=200" $r.code 200

$r = Invoke-RestMethod -Uri "$BASE/admin/products?keyword=PowerShell" -Headers $adminHeader
Assert-Equal "软删除后查不到" $r.data.total 0

# 4.7 必填项校验
try {
    Invoke-RestMethod -Uri "$BASE/admin/products" -Method POST `
        -Headers $adminHeader -ContentType "application/json" `
        -Body '{"price":10}'
    Write-Host "[FAIL] 缺name应返回400" -ForegroundColor Red
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert-Equal "缺name=400" $code 400
}

# ── T5 C端购物车status校验 ───────────────────────────────────
Write-Host "`n===== T5 购物车下架商品拦截 =====" -ForegroundColor Yellow

# 将商品1下架
Invoke-RestMethod -Uri "$BASE/admin/products/1/status?status=0" `
    -Method PUT -Headers $adminHeader | Out-Null

# 普通用户尝试加入购物车 → 400
try {
    Invoke-RestMethod -Uri "$BASE/cart" -Method POST `
        -Headers $userHeader -ContentType "application/json" `
        -Body '{"productId":1,"quantity":1}'
    Write-Host "[FAIL] 下架商品加购物车应返回400" -ForegroundColor Red
} catch {
    $body = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    $msg  = $body.msg
    Assert-Equal "下架商品拦截msg" ($msg -like "*下架*") $true
    Write-Host "返回消息：$msg"
}

# 恢复上架
Invoke-RestMethod -Uri "$BASE/admin/products/1/status?status=1" `
    -Method PUT -Headers $adminHeader | Out-Null
Write-Host "商品1已恢复上架"

# ── 汇总 ─────────────────────────────────────────────────────
Write-Host "`n===== 测试完成 =====" -ForegroundColor Yellow
