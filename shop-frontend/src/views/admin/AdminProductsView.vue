<template>
  <div class="admin-layout">
    <el-container>
      <el-aside width="200px" class="aside">
        <div class="logo">ShopAdmin</div>
        <el-menu :default-active="$route.path" router>
          <el-menu-item index="/admin/dashboard">首页</el-menu-item>
          <el-menu-item index="/admin/products">商品管理</el-menu-item>
          <el-menu-item index="/admin/categories">分类管理</el-menu-item>
          <el-menu-item index="/admin/brands">品牌管理</el-menu-item>
        </el-menu>
      </el-aside>
      <el-container>
        <el-header class="header">
          <span>欢迎，{{ adminStore.adminUser?.nickname }}</span>
          <el-button type="danger" text @click="handleLogout">退出</el-button>
        </el-header>
        <el-main>
          <!-- 搜索栏 -->
          <el-card class="filter-card">
            <el-row :gutter="12" align="middle">
              <el-col :span="5">
                <el-input v-model="filters.keyword" placeholder="商品名称" clearable @keyup.enter="fetchProducts" />
              </el-col>
              <el-col :span="4">
                <el-select v-model="filters.categoryId" placeholder="分类" clearable style="width:100%">
                  <el-option v-for="c in flatCategories" :key="c.id" :label="c.label" :value="c.id" />
                </el-select>
              </el-col>
              <el-col :span="4">
                <el-select v-model="filters.brandId" placeholder="品牌" clearable style="width:100%">
                  <el-option v-for="b in brands" :key="b.id" :label="b.name" :value="b.id" />
                </el-select>
              </el-col>
              <el-col :span="4">
                <el-select v-model="filters.status" placeholder="状态" clearable style="width:100%">
                  <el-option label="上架" :value="1" />
                  <el-option label="下架" :value="0" />
                  <el-option label="草稿" :value="2" />
                </el-select>
              </el-col>
              <el-col :span="4">
                <el-button type="primary" @click="fetchProducts">搜索</el-button>
                <el-button @click="resetFilters">重置</el-button>
              </el-col>
              <el-col :span="3" style="text-align:right">
                <el-button type="success" @click="$router.push('/admin/products/add')">新增商品</el-button>
              </el-col>
            </el-row>
          </el-card>

          <!-- 表格 -->
          <el-card style="margin-top:12px">
            <el-table :data="products" v-loading="loading" style="width:100%">
              <el-table-column prop="id" label="ID" width="70" />
              <el-table-column prop="name" label="名称" min-width="180" />
              <el-table-column label="价格" width="100">
                <template #default="{ row }">¥{{ row.price }}</template>
              </el-table-column>
              <el-table-column prop="stock" label="库存" width="80" />
              <el-table-column prop="categoryName" label="分类" width="100" />
              <el-table-column prop="brandName" label="品牌" width="100" />
              <el-table-column label="状态" width="100">
                <template #default="{ row }">
                  <el-switch
                    :model-value="row.status === 1"
                    :loading="row._toggling"
                    @change="(val) => handleToggleStatus(row, val)"
                  />
                </template>
              </el-table-column>
              <el-table-column label="操作" width="150" fixed="right">
                <template #default="{ row }">
                  <el-button size="small" @click="$router.push(`/admin/products/${row.id}/edit`)">编辑</el-button>
                  <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>

            <el-pagination
              class="pagination"
              v-model:current-page="pagination.page"
              v-model:page-size="pagination.size"
              :total="pagination.total"
              :page-sizes="[10, 20, 50]"
              layout="total, sizes, prev, pager, next"
              @size-change="fetchProducts"
              @current-change="fetchProducts"
            />
          </el-card>
        </el-main>
      </el-container>
    </el-container>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useAdminStore } from '@/stores/admin'
import {
  getAdminProducts, deleteAdminProduct, toggleProductStatus,
  getCategoryTree, getAllBrands,
} from '@/api/admin'

const router     = useRouter()
const adminStore = useAdminStore()
const loading    = ref(false)
const products   = ref([])
const flatCategories = ref([])
const brands     = ref([])

const filters = reactive({ keyword: '', categoryId: null, brandId: null, status: null })
const pagination = reactive({ page: 1, size: 10, total: 0 })

function handleLogout() {
  adminStore.logout()
  router.push('/admin/login')
}

function resetFilters() {
  Object.assign(filters, { keyword: '', categoryId: null, brandId: null, status: null })
  pagination.page = 1
  fetchProducts()
}

async function fetchProducts() {
  loading.value = true
  try {
    const data = await getAdminProducts({
      page: pagination.page,
      size: pagination.size,
      keyword: filters.keyword || undefined,
      categoryId: filters.categoryId || undefined,
      brandId: filters.brandId || undefined,
      status: filters.status ?? undefined,
    })
    products.value = (data.list || []).map(p => ({ ...p, _toggling: false }))
    pagination.total = data.total
  } catch (err) {
    ElMessage.error(err.message || '获取商品失败')
  } finally {
    loading.value = false
  }
}

async function handleToggleStatus(row, val) {
  row._toggling = true
  try {
    await toggleProductStatus(row.id, val ? 1 : 0)
    row.status = val ? 1 : 0
    ElMessage.success(val ? '上架成功' : '下架成功')
  } catch (err) {
    ElMessage.error(err.message || '操作失败')
  } finally {
    row._toggling = false
  }
}

async function handleDelete(row) {
  await ElMessageBox.confirm(`确认删除商品「${row.name}」？`, '提示', { type: 'warning' })
  try {
    await deleteAdminProduct(row.id)
    ElMessage.success('删除成功')
    fetchProducts()
  } catch (err) {
    ElMessage.error(err.message || '删除失败')
  }
}

function flattenTree(nodes, prefix = '') {
  const result = []
  for (const node of nodes) {
    result.push({ id: node.id, label: prefix + node.name })
    if (node.children?.length) {
      result.push(...flattenTree(node.children, prefix + '　'))
    }
  }
  return result
}

onMounted(async () => {
  fetchProducts()
  try {
    const tree = await getCategoryTree()
    flatCategories.value = flattenTree(tree || [])
  } catch {}
  try {
    const bs = await getAllBrands()
    brands.value = bs || []
  } catch {}
})
</script>

<style scoped>
.admin-layout { height: 100vh; }
.aside { background: #001529; }
.logo { color: #fff; font-size: 18px; font-weight: bold; padding: 20px; text-align: center; border-bottom: 1px solid #0d2745; }
.aside .el-menu { border-right: none; background: #001529; }
.aside .el-menu-item { color: #a6adb4; }
.aside .el-menu-item.is-active { color: #fff; background: #1890ff; }
.header { background: #fff; border-bottom: 1px solid #e8e8e8; display: flex; justify-content: flex-end; align-items: center; gap: 16px; padding: 0 24px; }
.filter-card .el-row { flex-wrap: wrap; gap: 8px 0; }
.pagination { margin-top: 16px; justify-content: flex-end; display: flex; }
</style>
