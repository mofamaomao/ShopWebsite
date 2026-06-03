<template>
  <div class="admin-layout">
    <el-container>
      <el-aside width="200px" class="aside">
        <div class="logo">ShopAdmin</div>
        <el-menu :default-active="'/admin/products'" router>
          <el-menu-item index="/admin/dashboard">首页</el-menu-item>
          <el-menu-item index="/admin/products">商品管理</el-menu-item>
          <el-menu-item index="/admin/categories">分类管理</el-menu-item>
          <el-menu-item index="/admin/brands">品牌管理</el-menu-item>
        </el-menu>
      </el-aside>
      <el-container>
        <el-header class="header">
          <el-button text @click="$router.back()">← 返回</el-button>
          <span>{{ isEdit ? '编辑商品' : '新增商品' }}</span>
          <el-button type="danger" text @click="handleLogout">退出</el-button>
        </el-header>
        <el-main>
          <el-card>
            <el-form :model="form" :rules="rules" ref="formRef" label-width="100px" style="max-width:600px">
              <el-form-item label="商品名称" prop="name">
                <el-input v-model="form.name" placeholder="请输入商品名称" />
              </el-form-item>
              <el-form-item label="价格" prop="price">
                <el-input-number v-model="form.price" :precision="2" :min="0.01" style="width:200px" />
              </el-form-item>
              <el-form-item label="库存" prop="stock">
                <el-input-number v-model="form.stock" :min="0" style="width:200px" />
              </el-form-item>
              <el-form-item label="分类" prop="categoryId">
                <el-cascader
                  v-model="categoryPath"
                  :options="categoryOptions"
                  :props="{ value: 'id', label: 'name', children: 'children', checkStrictly: true, emitPath: false }"
                  placeholder="选择分类"
                  clearable
                  style="width:100%"
                  @change="onCategoryChange"
                />
              </el-form-item>
              <el-form-item label="品牌" prop="brandId">
                <el-select v-model="form.brandId" placeholder="选择品牌" clearable style="width:100%">
                  <el-option v-for="b in brands" :key="b.id" :label="b.name" :value="b.id" />
                </el-select>
              </el-form-item>
              <el-form-item label="图片URL">
                <el-input v-model="form.imageUrl" placeholder="图片URL（可选）" />
              </el-form-item>
              <el-form-item label="描述">
                <el-input v-model="form.description" type="textarea" :rows="4" placeholder="商品描述（可选）" />
              </el-form-item>
              <el-form-item label="状态" prop="status">
                <el-radio-group v-model="form.status">
                  <el-radio :value="1">上架</el-radio>
                  <el-radio :value="0">下架</el-radio>
                  <el-radio :value="2">草稿</el-radio>
                </el-radio-group>
              </el-form-item>
              <el-form-item>
                <el-button type="primary" :loading="saving" @click="handleSubmit">保存</el-button>
                <el-button @click="$router.back()">取消</el-button>
              </el-form-item>
            </el-form>
          </el-card>
        </el-main>
      </el-container>
    </el-container>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useAdminStore } from '@/stores/admin'
import { createAdminProduct, updateAdminProduct, getAdminProducts, getCategoryTree, getAllBrands } from '@/api/admin'

const route      = useRoute()
const router     = useRouter()
const adminStore = useAdminStore()
const formRef    = ref(null)
const saving     = ref(false)
const brands     = ref([])
const categoryOptions = ref([])
const categoryPath    = ref(null)

const isEdit = computed(() => !!route.params.id)

const form = reactive({
  name: '', price: null, stock: 0,
  categoryId: null, brandId: null,
  imageUrl: '', description: '', status: 2,
})

const rules = {
  name:    [{ required: true, message: '请输入商品名称', trigger: 'blur' }],
  price:   [{ required: true, message: '请输入价格', trigger: 'blur' }],
  stock:   [{ required: true, message: '请输入库存', trigger: 'blur' }],
}

function onCategoryChange(val) {
  form.categoryId = val
}

function handleLogout() {
  adminStore.logout()
  router.push('/admin/login')
}

async function handleSubmit() {
  await formRef.value.validate()
  saving.value = true
  try {
    const payload = {
      name: form.name, price: form.price, stock: form.stock,
      categoryId: form.categoryId, brandId: form.brandId,
      imageUrl: form.imageUrl || null, description: form.description || null,
      status: form.status,
    }
    if (isEdit.value) {
      await updateAdminProduct(route.params.id, payload)
    } else {
      await createAdminProduct(payload)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
    router.push('/admin/products')
  } catch (err) {
    ElMessage.error(err.message || '保存失败')
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  try {
    const tree = await getCategoryTree()
    categoryOptions.value = tree || []
  } catch {}
  try {
    const bs = await getAllBrands()
    brands.value = bs || []
  } catch {}

  if (isEdit.value) {
    try {
      const data = await getAdminProducts({ page: 1, size: 1000 })
      const product = (data.list || []).find(p => String(p.id) === String(route.params.id))
      if (product) {
        Object.assign(form, {
          name: product.name, price: product.price, stock: product.stock,
          categoryId: product.categoryId, brandId: product.brandId,
          imageUrl: product.imageUrl, description: product.description,
          status: product.status,
        })
        categoryPath.value = product.categoryId
      }
    } catch {}
  }
})
</script>

<style scoped>
.admin-layout { height: 100vh; }
.aside { background: #001529; }
.logo { color: #fff; font-size: 18px; font-weight: bold; padding: 20px; text-align: center; border-bottom: 1px solid #0d2745; }
.aside .el-menu { border-right: none; background: #001529; }
.aside .el-menu-item { color: #a6adb4; }
.aside .el-menu-item.is-active { color: #fff; background: #1890ff; }
.header { background: #fff; border-bottom: 1px solid #e8e8e8; display: flex; justify-content: space-between; align-items: center; padding: 0 24px; }
</style>
