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
              <el-button type="danger" size="small" text @click="handleRemove(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
        <div class="cart-footer">
          <span class="total">合计：<strong>¥{{ cart.total }}</strong></span>
          <el-button type="primary" size="large" @click="handleCheckout">去结算</el-button>
        </div>
      </template>
      <el-empty v-else-if="!loading" description="购物车是空的">
        <el-button type="primary" @click="$router.push('/')">去逛逛</el-button>
      </el-empty>
    </div>

    <!-- 地址 + 积分结算弹窗 -->
    <el-dialog v-model="addrDialogVisible" title="确认订单" width="580px" destroy-on-close>
      <div v-loading="addrLoading" class="checkout-body">
        <!-- 地址选择 -->
        <div v-if="!addrLoading && addresses.length === 0">
          <el-empty description="暂无收货地址">
            <el-button type="primary" @click="$router.push('/user/addresses')">去添加地址</el-button>
          </el-empty>
        </div>
        <div v-else>
          <div class="section-title">收货地址</div>
          <div class="addr-options">
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

          <!-- 积分抵扣 -->
          <el-divider />
          <div class="section-title">积分优惠</div>
          <div class="points-row" v-if="pointsInfo">
            <div class="points-desc">
              当前积分 <strong>{{ pointsInfo.balance }}</strong>，
              本单最多可抵扣 <strong class="deduction-text">¥{{ maxDeductionDisplay }}</strong>
            </div>
            <el-switch
              v-model="usePoints"
              :disabled="pointsInfo.balance === 0"
              active-text="使用积分"
            />
          </div>

          <!-- 金额汇总 -->
          <el-divider />
          <div class="price-summary">
            <div class="price-row">
              <span>商品合计</span>
              <span>¥{{ cart ? cart.total : '0.00' }}</span>
            </div>
            <div class="price-row deduction" v-if="usePoints && pointsDeduction > 0">
              <span>积分抵扣（-{{ usablePoints }} 分）</span>
              <span class="deduct-val">-¥{{ pointsDeduction.toFixed(2) }}</span>
            </div>
            <div class="price-row total-row">
              <span>实付金额</span>
              <strong class="final-price">¥{{ finalPrice }}</strong>
            </div>
          </div>
        </div>
      </div>
      <template #footer>
        <el-button @click="addrDialogVisible = false">取消</el-button>
        <el-button
          type="primary"
          :disabled="!selectedAddrId || addresses.length === 0"
          :loading="ordering"
          @click="doCheckout"
        >确认下单</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getCart } from '@/api/cart'
import { createOrder } from '@/api/order'
import { getUserAddresses } from '@/api/address'
import { getPointsBalance } from '@/api/points'
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

const usePoints = ref(false)
const pointsInfo = ref(null)

// 积分抵扣计算（与后端逻辑保持一致）
const usablePoints = computed(() => {
  if (!usePoints.value || !pointsInfo.value || !cart.value) return 0
  const { balance, redeemRate, maxRedeemPct } = pointsInfo.value
  const total = parseFloat(cart.value.total)
  const maxDeductAmt = total * maxRedeemPct
  const maxDeductPts = Math.floor(maxDeductAmt * redeemRate)
  return Math.min(balance, maxDeductPts)
})

const pointsDeduction = computed(() => {
  if (!pointsInfo.value || usablePoints.value === 0) return 0
  return Math.floor(usablePoints.value * 100 / pointsInfo.value.redeemRate) / 100
})

const finalPrice = computed(() => {
  if (!cart.value) return '0.00'
  return (parseFloat(cart.value.total) - pointsDeduction.value).toFixed(2)
})

const maxDeductionDisplay = computed(() => {
  if (!pointsInfo.value || !cart.value) return '0.00'
  const { balance, redeemRate, maxRedeemPct } = pointsInfo.value
  const total = parseFloat(cart.value.total)
  const maxPts = Math.min(balance, Math.floor(total * maxRedeemPct * redeemRate))
  return (Math.floor(maxPts * 100 / redeemRate) / 100).toFixed(2)
})

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
  usePoints.value = false
  try {
    const [addrs, pts] = await Promise.all([getUserAddresses(), getPointsBalance()])
    addresses.value = addrs
    pointsInfo.value = pts
    const defaultAddr = addrs.find(a => a.isDefault) || addrs[0]
    selectedAddrId.value = defaultAddr?.id ?? null
  } catch (err) {
    ElMessage.error(err.message || '加载失败')
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
    const order = await createOrder({
      items,
      addressId: selectedAddrId.value,
      usePoints: usePoints.value,
    })
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

/* 结算弹窗 */
.checkout-body { padding: 0 4px; }
.section-title { font-size: 13px; font-weight: 600; color: #606266; margin-bottom: 10px; }
.addr-options { display: flex; flex-direction: column; gap: 8px; }
.addr-option {
  display: flex;
  align-items: flex-start;
  padding: 10px 14px;
  border: 1px solid #e4e7ed;
  border-radius: 8px;
  cursor: pointer;
  transition: border-color 0.2s;
}
.addr-option:hover { border-color: #c6e2ff; }
.addr-option--selected { border-color: #409eff; background: #ecf5ff; }
.addr-info { flex: 1; }
.addr-top { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
.receiver { font-size: 14px; font-weight: 600; color: #303133; }
.phone { font-size: 13px; color: #606266; }
.addr-text { font-size: 13px; color: #909399; }
.addr-add-link { margin-top: 8px; text-align: right; }

.points-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.points-desc { font-size: 13px; color: #606266; }
.deduction-text { color: #e6a23c; }

.price-summary { display: flex; flex-direction: column; gap: 8px; }
.price-row {
  display: flex;
  justify-content: space-between;
  font-size: 14px;
  color: #606266;
}
.deduction { color: #67c23a; }
.deduct-val { color: #67c23a; font-weight: 600; }
.total-row { font-size: 15px; color: #303133; margin-top: 4px; }
.final-price { color: #f56c6c; font-size: 20px; }
</style>
