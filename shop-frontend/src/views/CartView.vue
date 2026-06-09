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
          <el-button type="primary" size="large" @click="handleCheckout">
            去结算
          </el-button>
        </div>
      </template>
      <el-empty v-else-if="!loading" description="购物车是空的">
        <el-button type="primary" @click="$router.push('/')">去逛逛</el-button>
      </el-empty>
    </div>

    <!-- 地址选择弹窗 -->
    <el-dialog
      v-model="addrDialogVisible"
      title="选择收货地址"
      width="560px"
      destroy-on-close
    >
      <div v-loading="addrLoading" class="addr-dialog-body">
        <div v-if="!addrLoading && addresses.length === 0">
          <el-empty description="暂无收货地址">
            <el-button type="primary" @click="$router.push('/user/addresses')">去添加地址</el-button>
          </el-empty>
        </div>
        <div v-else class="addr-options">
          <div
            v-for="addr in addresses"
            :key="addr.id"
            class="addr-option"
            :class="{ 'addr-option--selected': selectedAddrId === addr.id }"
            @click="selectedAddrId = addr.id"
          >
            <el-radio
              :model-value="selectedAddrId"
              :label="addr.id"
              style="margin-right: 8px"
              @change="selectedAddrId = addr.id"
            />
            <div class="addr-info">
              <div class="addr-top">
                <span class="receiver">{{ addr.receiver }}</span>
                <span class="phone">{{ addr.phone }}</span>
                <el-tag v-if="addr.isDefault" type="success" size="small" effect="plain">默认</el-tag>
              </div>
              <div class="addr-text">{{ addr.province }} {{ addr.city }} {{ addr.district }} {{ addr.detail }}</div>
            </div>
          </div>
        </div>
        <div class="addr-add-link">
          <el-button text size="small" @click="$router.push('/user/addresses')">+ 管理收货地址</el-button>
        </div>
      </div>
      <template #footer>
        <el-button @click="addrDialogVisible = false">取消</el-button>
        <el-button
          type="primary"
          :disabled="!selectedAddrId"
          :loading="ordering"
          @click="doCheckout"
        >确认下单</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getCart } from '@/api/cart'
import { createOrder } from '@/api/order'
import { getUserAddresses } from '@/api/address'
import { useCartStore } from '@/stores/cart'

const router = useRouter()
const cartStore = useCartStore()
const cart = ref(null)
const loading = ref(false)
const ordering = ref(false)

const addrDialogVisible = ref(false)
const addresses = ref([])
const selectedAddrId = ref(null)
const addrLoading = ref(false)

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
  addrDialogVisible.value = true
  addrLoading.value = true
  try {
    const addrs = await getUserAddresses()
    addresses.value = addrs
    const defaultAddr = addrs.find(a => a.isDefault) || addrs[0]
    selectedAddrId.value = defaultAddr?.id ?? null
  } catch (err) {
    ElMessage.error(err.message || '获取地址失败')
    addrDialogVisible.value = false
  } finally {
    addrLoading.value = false
  }
}

async function doCheckout() {
  if (!selectedAddrId.value) {
    ElMessage.warning('请选择收货地址')
    return
  }
  const items = cart.value.items.map(i => ({ productId: i.productId, quantity: i.quantity }))
  ordering.value = true
  try {
    const order = await createOrder({ items, addressId: selectedAddrId.value })
    cartStore.clearCart()
    addrDialogVisible.value = false
    router.push({ path: '/order-pay', query: { orderId: order.orderId, totalPrice: order.totalPrice } })
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

/* 地址选择弹窗 */
.addr-dialog-body { padding: 4px 0; }
.addr-options { display: flex; flex-direction: column; gap: 8px; }
.addr-option {
  display: flex;
  align-items: flex-start;
  padding: 12px 16px;
  border: 1px solid #e4e7ed;
  border-radius: 8px;
  cursor: pointer;
  transition: border-color 0.2s;
}
.addr-option:hover { border-color: #c6e2ff; }
.addr-option--selected { border-color: #409eff; background: #ecf5ff; }
.addr-info { flex: 1; }
.addr-top {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}
.receiver { font-size: 14px; font-weight: 600; color: #303133; }
.phone { font-size: 13px; color: #606266; }
.addr-text { font-size: 13px; color: #909399; }
.addr-add-link {
  margin-top: 12px;
  text-align: right;
}
</style>
