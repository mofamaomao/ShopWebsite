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
                <span>分类管理</span>
                <el-button type="primary" size="small" @click="openDialog(null)">新增一级分类</el-button>
              </div>
            </template>
            <el-table :data="tree" v-loading="loading" row-key="id" :tree-props="{ children: 'children' }">
              <el-table-column prop="name" label="分类名称" />
              <el-table-column prop="sort" label="排序" width="80" />
              <el-table-column label="操作" width="200">
                <template #default="{ row }">
                  <el-button size="small" @click="openDialog(row.parentId, row)">编辑</el-button>
                  <el-button size="small" type="success" @click="openDialog(row.id)">添加子分类</el-button>
                  <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>
          </el-card>
        </el-main>
      </el-container>
    </el-container>

    <!-- 新增/编辑弹窗 -->
    <el-dialog v-model="dialogVisible" :title="editId ? '编辑分类' : '新增分类'" width="400px">
      <el-form :model="form" :rules="rules" ref="formRef" label-width="80px">
        <el-form-item label="名称" prop="name">
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="form.sort" :min="0" />
        </el-form-item>
        <el-form-item label="图标URL">
          <el-input v-model="form.iconUrl" />
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
import { getCategoryTree, createCategory, updateCategory, deleteCategory } from '@/api/admin'

const router     = useRouter()
const adminStore = useAdminStore()
const loading    = ref(false)
const saving     = ref(false)
const tree       = ref([])
const formRef    = ref(null)
const dialogVisible = ref(false)
const editId     = ref(null)
const parentId   = ref(null)

const form = reactive({ name: '', sort: 0, iconUrl: '' })
const rules = { name: [{ required: true, message: '请输入分类名称', trigger: 'blur' }] }

function handleLogout() {
  adminStore.logout()
  router.push('/admin/login')
}

async function fetchTree() {
  loading.value = true
  try {
    tree.value = await getCategoryTree() || []
  } catch (err) {
    ElMessage.error(err.message || '获取分类失败')
  } finally {
    loading.value = false
  }
}

function openDialog(pid, row = null) {
  editId.value  = row?.id || null
  parentId.value = pid
  Object.assign(form, row ? { name: row.name, sort: row.sort ?? 0, iconUrl: row.iconUrl || '' }
                           : { name: '', sort: 0, iconUrl: '' })
  dialogVisible.value = true
}

async function handleSave() {
  await formRef.value.validate()
  saving.value = true
  try {
    const payload = { name: form.name, sort: form.sort, iconUrl: form.iconUrl || null, parentId: parentId.value }
    if (editId.value) {
      await updateCategory(editId.value, payload)
    } else {
      await createCategory(payload)
    }
    ElMessage.success('保存成功')
    dialogVisible.value = false
    fetchTree()
  } catch (err) {
    ElMessage.error(err.message || '保存失败')
  } finally {
    saving.value = false
  }
}

async function handleDelete(row) {
  await ElMessageBox.confirm(`确认删除分类「${row.name}」？子分类不会自动删除。`, '提示', { type: 'warning' })
  try {
    await deleteCategory(row.id)
    ElMessage.success('删除成功')
    fetchTree()
  } catch (err) {
    ElMessage.error(err.message || '删除失败')
  }
}

onMounted(fetchTree)
</script>

<style scoped>
.admin-layout { height: 100vh; }
.aside { background: #001529; }
.logo { color: #fff; font-size: 18px; font-weight: bold; padding: 20px; text-align: center; border-bottom: 1px solid #0d2745; }
.aside .el-menu { border-right: none; background: #001529; }
.aside .el-menu-item { color: #a6adb4; }
.aside .el-menu-item.is-active { color: #fff; background: #1890ff; }
.header { background: #fff; border-bottom: 1px solid #e8e8e8; display: flex; justify-content: flex-end; align-items: center; gap: 16px; padding: 0 24px; }
</style>
