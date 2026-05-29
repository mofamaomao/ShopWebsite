<template>
  <div class="product-page">
    <div v-loading="loading" class="product-detail">
      <template v-if="product">
        <div class="product-img-wrap">
          <el-icon size="120" color="#c0c4cc"><Picture /></el-icon>
        </div>
        <div class="product-meta">
          <h2>{{ product.name }}</h2>
          <div class="price">¥{{ product.price }}</div>
          <div class="desc">{{ product.description }}</div>
          <div class="stock" :class="{ 'low-stock': product.stock < 10 }">
            库存：{{ product.stock }} 件
          </div>
          <div class="actions">
            <el-input-number v-model="qty" :min="1" :max="product.stock" :disabled="product.stock === 0" />
            <el-button type="primary" size="large" :disabled="product.stock === 0" @click="handleAddCart">
              {{ product.stock === 0 ? '已售罄' : '加入购物车' }}
            </el-button>
          </div>
        </div>
      </template>
      <el-empty v-else-if="!loading" description="商品不存在" />
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Picture } from '@element-plus/icons-vue'
import { getProduct } from '@/api/product'
import { useUserStore } from '@/stores/user'
import { useCartStore } from '@/stores/cart'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const cartStore = useCartStore()
const product = ref(null)
const loading = ref(false)
const qty = ref(1)

onMounted(async () => {
  loading.value = true
  try {
    product.value = await getProduct(route.params.id)
  } finally {
    loading.value = false
  }
})

async function handleAddCart() {
  if (!userStore.isLoggedIn) {
    ElMessage.warning('请先登录')
    router.push('/login')
    return
  }
  if (qty.value > product.value.stock) {
    ElMessage.warning(`数量不能超过库存（${product.value.stock} 件）`)
    qty.value = product.value.stock
    return
  }
  try {
    await cartStore.addItem(product.value.id, qty.value)
    ElMessage.success('已加入购物车')
  } catch (err) {
    ElMessage.error(err.message || '操作失败')
  }
}
</script>

<style scoped>
.product-page {
  max-width: 900px;
  margin: 32px auto;
  padding: 0 16px;
}
.product-detail {
  display: flex;
  gap: 40px;
  background: #fff;
  padding: 32px;
  border-radius: 8px;
  min-height: 300px;
}
.product-img-wrap {
  width: 300px;
  height: 300px;
  background: #f5f7fa;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  flex-shrink: 0;
}
.product-meta { flex: 1; }
.product-meta h2 { margin: 0 0 16px; font-size: 22px; }
.price { color: #f56c6c; font-size: 28px; font-weight: bold; margin-bottom: 16px; }
.desc { color: #606266; margin-bottom: 16px; line-height: 1.6; }
.stock { color: #909399; margin-bottom: 24px; }
.low-stock { color: #e6a23c; }
.actions { display: flex; gap: 16px; align-items: center; }
</style>
