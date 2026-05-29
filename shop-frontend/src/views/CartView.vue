<template>
  <div class="cart-page">
    <h2>我的购物车</h2>
    <div v-loading="loading">
      <template v-if="cart && cart.items && cart.items.length > 0">
        <el-table :data="cart.items" style="width: 100%">
          <el-table-column prop="productName" label="商品名称" />
          <el-table-column label="单价" width="120">
            <template #default="{ row }">¥{{ row.price }}</template>
          </el-table-column>
          <el-table-column label="数量" width="180">
            <template #default="{ row }">
              <el-input-number
                v-model="row.quantity"
                :min="1"
                :max="row.stock"
                size="small"
                @change="(val) => handleQuantityChange(row, val)"
              />
            </template>
          </el-table-column>
          <el-table-column label="小计" width="120">
            <template #default="{ row }">¥{{ row.subtotal }}</template>
          </el-table-column>
          <el-table-column label="操作" width="100">
            <template #default="{ row }">
              <el-button
                type="danger"
                size="small"
                text
                @click="handleRemove(row)"
              >删除</el-button>
            </template>
          </el-table-column>
        </el-table>
        <div class="cart-footer">
          <span class="total">合计：<strong>¥{{ cart.total }}</strong></span>
          <el-button type="primary" size="large" :loading="ordering" @click="handleCheckout">
            去结算
          </el-button>
        </div>
      </template>
      <el-empty v-else-if="!loading" description="购物车是空的">
        <el-button type="primary" @click="$router.push('/')">去逛逛</el-button>
      </el-empty>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getCart } from '@/api/cart'
import { createOrder } from '@/api/order'
import { useCartStore } from '@/stores/cart'

const router = useRouter()
const cartStore = useCartStore()
const cart = ref(null)
const loading = ref(false)
const ordering = ref(false)

async function fetchCart() {
  loading.value = true
  try {
    cart.value = await getCart()
  } finally {
    loading.value = false
  }
}

onMounted(fetchCart)

async function handleQuantityChange(row, val) {
  if (!val || val < 1) return
  try {
    await cartStore.updateItem(row.productId, val)
    await fetchCart()
  } catch (err) {
    ElMessage.error(err.message || '更新失败')
    await fetchCart()
  }
}

async function handleRemove(row) {
  try {
    await cartStore.removeItem(row.productId)
    await fetchCart()
  } catch (err) {
    ElMessage.error(err.message || '删除失败')
  }
}

async function handleCheckout() {
  const items = cart.value.items.map(i => ({ productId: i.productId, quantity: i.quantity }))
  ordering.value = true
  try {
    const order = await createOrder({ items })
    router.push({ path: '/order-success', query: { orderId: order.orderId, total: order.totalPrice } })
  } catch (err) {
    ElMessage.error(err.message || '下单失败')
  } finally {
    ordering.value = false
  }
}
</script>

<style scoped>
.cart-page {
  max-width: 900px;
  margin: 32px auto;
  padding: 0 16px;
}
.cart-page h2 { margin-bottom: 24px; }
.cart-footer {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 24px;
  margin-top: 24px;
  padding: 16px 24px;
  background: #f5f7fa;
  border-radius: 4px;
}
.total { font-size: 16px; }
.total strong { color: #f56c6c; font-size: 22px; }
</style>
