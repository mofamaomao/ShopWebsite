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
          <el-card>
            <template #header>
              <div style="display:flex;justify-content:space-between;align-items:center">
                <el-input v-model="keyword" placeholder="品牌名称搜索" style="width:200px" clearable @keyup.enter="fetchBrands" />
                <el-button type="primary" @click="openDialog()">新增品牌</el-button>
              </div>
            </template>
            <el-table :data="brands" v-loading="loading" style="width:100%">
              <el-table-column prop="id" label="ID" width="70" />
              <el-table-column prop="name" label="品牌名称" />
              <el-table-column prop="description" label="描述" show-overflow-tooltip />
              <el-table-column label="操作" width="150">
                <template #default="{ row }">
                  <el-button size="small" @click="openDialog(row)">编辑</el-button>
                  <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>
            <el-pagination
              class="pagination"
              v-model:current-page="pagination.page"
              v-model:page-size="pagination.size"
              :total="pagination.total"
              layout="total, prev, pager, next"
              @current-change="fetchBrands"
            />
          </el-card>
        </el-main>
      </el-container>
    </el-container>

    <el-dialog v-model="dialogVisible" :title="editId ? '编辑品牌' : '新增品牌'" width="420px">
      <el-form :model="form" :rules="rules" ref="formRef" label-width="80px">
        <el-form-item label="名称" prop="name">
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="Logo URL">
          <el-input v-model="form.logoUrl" />
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" type="textarea" :rows="3" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="handleSave">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useAdminStore } from '@/stores/admin'
import { getBrands, createBrand, updateBrand, deleteBrand } from '@/api/admin'

const router     = useRouter()
const adminStore = useAdminStore()
const loading    = ref(false)
const saving     = ref(false)
const brands     = ref([])
const keyword    = ref('')
const formRef    = ref(null)
const dialogVisible = ref(false)
const editId     = ref(null)
const pagination = reactive({ page: 1, size: 10, total: 0 })

const form = reactive({ name: '', logoUrl: '', description: '' })
const rules = { name: [{ required: true, message: '请输入品牌名称', trigger: 'blur' }] }

function handleLogout() {
  adminStore.logout()
  router.push('/admin/login')
}

async function fetchBrands() {
  loading.value = true
  try {
    const data = await getBrands({ page: pagination.page, size: pagination.size, keyword: keyword.value || undefined })
    brands.value = data.list || []
    pagination.total = data.total
  } catch (err) {
    ElMessage.error(err.message || '获取品牌失败')
  } finally {
    loading.value = false
  }
}

function openDialog(row = null) {
  editId.value = row?.id || null
  Object.assign(form, row ? { name: row.name, logoUrl: row.logoUrl || '', description: row.description || '' }
                           : { name: '', logoUrl: '', description: '' })
  dialogVisible.value = true
}

async function handleSave() {
  await formRef.value.validate()
  saving.value = true
  try {
    const payload = { name: form.name, logoUrl: form.logoUrl || null, description: form.description || null }
    if (editId.value) {
      await updateBrand(editId.value, payload)
    } else {
      await createBrand(payload)
    }
    ElMessage.success('保存成功')
    dialogVisible.value = false
    fetchBrands()
  } catch (err) {
    ElMessage.error(err.message || '保存失败')
  } finally {
    saving.value = false
  }
}

async function handleDelete(row) {
  await ElMessageBox.confirm(`确认删除品牌「${row.name}」？`, '提示', { type: 'warning' })
  try {
    await deleteBrand(row.id)
    ElMessage.success('删除成功')
    fetchBrands()
  } catch (err) {
    ElMessage.error(err.message || '删除失败')
  }
}

onMounted(fetchBrands)
</script>

<style scoped>
.admin-layout { height: 100vh; }
.aside { background: #001529; }
.logo { color: #fff; font-size: 18px; font-weight: bold; padding: 20px; text-align: center; border-bottom: 1px solid #0d2745; }
.aside .el-menu { border-right: none; background: #001529; }
.aside .el-menu-item { color: #a6adb4; }
.aside .el-menu-item.is-active { color: #fff; background: #1890ff; }
.header { background: #fff; border-bottom: 1px solid #e8e8e8; display: flex; justify-content: flex-end; align-items: center; gap: 16px; padding: 0 24px; }
.pagination { margin-top: 16px; justify-content: flex-end; display: flex; }
</style>
