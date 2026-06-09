<template>
  <div class="orders-page">
    <div class="page-header">
      <h2 class="page-title">我的订单</h2>
      <el-button :icon="Refresh" circle size="small" :loading="loading" @click="manualRefresh" />
    </div>

    <!-- 状态 Tab：name 用显式字符串，避免 Element Plus 对 name="" 的处理差异 -->
    <el-tabs v-model="activeTab" @tab-change="onTabChange">
      <el-tab-pane label="全部"   name="all" />
      <el-tab-pane label="待支付" name="PENDING_PAYMENT" />
      <el-tab-pane label="已支付" name="PAID" />
      <el-tab-pane label="已取消" name="CANCELLED" />
    </el-tabs>

    <!-- 加载中 -->
    <div v-if="loading" class="loading-wrap">
      <el-skeleton :rows="4" animated />
    </div>

    <!-- 空状态 -->
    <div v-else-if="orders.length === 0" class="empty-wrap">
      <el-empty description="暂无订单" />
      <p v-if="retryCount < MAX_RETRY" class="empty-hint">
        刚刚下单？订单正在处理中，{{ retryCountdown }} 秒后自动刷新…
      </p>
      <el-button v-else size="small" @click="manualRefresh">手动刷新</el-button>
    </div>

    <!-- 订单卡片列表 -->
    <template v-else>
      <div v-for="order in orders" :key="order.orderNo" class="order-card">
        <div class="card-header">
          <span class="order-no">订单号：{{ order.orderNo }}</span>
          <el-tag :type="statusType(order.status)" size="small">{{ statusLabel(order.status) }}</el-tag>
        </div>
        <div class="card-body">
          <div class="order-meta">
            <span>下单时间：{{ formatDate(order.createdAt) }}</span>
            <span v-if="order.payTime">支付时间：{{ formatDate(order.payTime) }}</span>
            <span class="item-count">共 {{ order.itemCount }} 件商品</span>
          </div>
          <div class="order-price">合计：<strong>¥{{ order.totalPrice }}</strong></div>
        </div>
        <div class="card-footer">
          <el-button size="small" @click="viewDetail(order.orderNo)">查看详情</el-button>
          <el-button
            v-if="order.status === 'PENDING_PAYMENT'"
            size="small"
            type="primary"
            @click="goPay(order.orderNo, order.totalPrice)"
          >去支付</el-button>
          <el-popconfirm
            v-if="order.status === 'PENDING_PAYMENT'"
            title="确认取消该订单？"
            confirm-button-text="确认取消"
            cancel-button-text="再想想"
            @confirm="doCancel(order.orderNo)"
          >
            <template #reference>
              <el-button size="small" type="danger" plain>取消订单</el-button>
            </template>
          </el-popconfirm>
        </div>
      </div>

      <!-- 分页 -->
      <div class="pagination-wrap">
        <el-pagination
          v-model:current-page="page"
          v-model:page-size="size"
          :page-sizes="[5, 10, 20]"
          :total="total"
          layout="total, sizes, prev, pager, next"
          @size-change="loadOrders"
          @current-change="loadOrders"
        />
      </div>
    </template>

    <!-- 详情弹窗 -->
    <el-dialog v-model="detailVisible" title="订单详情" width="680px" destroy-on-close>
      <div v-if="detailOrder" class="detail-wrap">
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="订单号" :span="2">{{ detailOrder.orderNo }}</el-descriptions-item>
          <el-descriptions-item label="状态">
            <el-tag :type="statusType(detailOrder.status)" size="small">{{ statusLabel(detailOrder.status) }}</el-tag>
          </el-descriptions-item>
          <el-descriptions-item label="合计">¥{{ detailOrder.totalPrice }}</el-descriptions-item>
          <el-descriptions-item label="下单时间">{{ formatDate(detailOrder.createdAt) }}</el-descriptions-item>
          <el-descriptions-item label="支付时间">{{ detailOrder.payTime ? formatDate(detailOrder.payTime) : '—' }}</el-descriptions-item>
          <el-descriptions-item v-if="detailOrder.cancelTime" label="取消时间" :span="2">
            {{ formatDate(detailOrder.cancelTime) }}
          </el-descriptions-item>
          <el-descriptions-item v-if="detailOrder.receiver" label="收货人">
            {{ detailOrder.receiver }}（{{ detailOrder.phone }}）
          </el-descriptions-item>
          <el-descriptions-item v-if="detailOrder.fullAddress" label="收货地址" :span="detailOrder.receiver ? 1 : 2">
            {{ detailOrder.fullAddress }}
          </el-descriptions-item>
        </el-descriptions>

        <h4 class="items-title">商品明细</h4>
        <el-table :data="detailOrder.items" size="small" border>
          <el-table-column label="商品" min-width="200">
            <template #default="{ row }">
              <div class="item-cell">
                <el-image
                  v-if="row.productImg"
                  :src="row.productImg"
                  style="width:48px;height:48px;object-fit:cover;border-radius:4px"
                  fit="cover"
                />
                <span class="item-name">{{ row.productName || '—' }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="单价" width="100">
            <template #default="{ row }">¥{{ row.price }}</template>
          </el-table-column>
          <el-table-column label="数量" prop="quantity" width="80" />
          <el-table-column label="小计" width="100">
            <template #default="{ row }">¥{{ row.subtotal }}</template>
          </el-table-column>
        </el-table>
      </div>
      <template #footer>
        <el-button @click="detailVisible = false">关闭</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { Refresh } from '@element-plus/icons-vue'
import { getUserOrders, getUserOrderDetail, cancelUserOrder } from '@/api/userOrder'

const router = useRouter()

// Tab 使用 'all' 而非 '' 避免 Element Plus 对空字符串的处理差异
const activeTab  = ref('all')
const orders     = ref([])
const total      = ref(0)
const page       = ref(1)
const size       = ref(10)
const loading    = ref(false)

const detailVisible = ref(false)
const detailOrder   = ref(null)

// MQ 异步延迟自动重试
const MAX_RETRY      = 3
const RETRY_INTERVAL = 2000
let   retryCount     = ref(0)
const retryCountdown = ref(2)
let   retryTimer     = null
let   countdownTimer = null

onMounted(loadOrders)
onUnmounted(clearRetry)

// 将 Tab 名称映射为 API 的 status 参数（'all' → '' 表示不过滤）
function tabToStatus(tab) {
  return tab === 'all' ? '' : tab
}

async function loadOrders() {
  clearRetry()
  loading.value = true
  try {
    const res = await getUserOrders({
      page: page.value,
      size: size.value,
      status: tabToStatus(activeTab.value)
    })
    orders.value = res.list
    total.value  = res.total

    // 首次加载为空时自动重试，处理 MQ Consumer 异步落库延迟
    if (orders.value.length === 0 && retryCount.value < MAX_RETRY) {
      scheduleRetry()
    }
  } finally {
    loading.value = false
  }
}

function scheduleRetry() {
  retryCountdown.value = RETRY_INTERVAL / 1000
  countdownTimer = setInterval(() => {
    retryCountdown.value--
  }, 1000)
  retryTimer = setTimeout(async () => {
    retryCount.value++
    clearInterval(countdownTimer)
    await loadOrders()
  }, RETRY_INTERVAL)
}

function clearRetry() {
  clearTimeout(retryTimer)
  clearInterval(countdownTimer)
}

function manualRefresh() {
  retryCount.value = 0
  loadOrders()
}

function onTabChange() {
  page.value = 1
  retryCount.value = 0
  loadOrders()
}

async function viewDetail(orderNo) {
  const res = await getUserOrderDetail(orderNo)
  detailOrder.value   = res
  detailVisible.value = true
}

function goPay(orderNo, totalPrice) {
  router.push({ name: 'OrderPay', query: { orderId: orderNo, totalPrice } })
}

async function doCancel(orderNo) {
  await cancelUserOrder(orderNo)
  ElMessage.success('订单已取消')
  loadOrders()
}

function statusLabel(s) {
  const map = { PENDING_PAYMENT: '待支付', PAID: '已支付', CANCELLED: '已取消', PROCESSING: '处理中' }
  return map[s] || s
}

function statusType(s) {
  const map = { PENDING_PAYMENT: 'warning', PAID: 'success', CANCELLED: 'info', PROCESSING: '' }
  return map[s] || ''
}

function formatDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleString('zh-CN', { hour12: false })
}
</script>

<style scoped>
.orders-page {
  max-width: 900px;
  margin: 24px auto;
  padding: 0 16px;
}
.page-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 16px;
}
.page-title {
  font-size: 22px;
  font-weight: 600;
  margin: 0;
}
.loading-wrap {
  padding: 16px 0;
}
.empty-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.empty-hint {
  font-size: 13px;
  color: #909399;
  margin-top: -8px;
}
.order-card {
  border: 1px solid #e4e7ed;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
  background: #fff;
}
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 10px;
}
.order-no {
  font-size: 13px;
  color: #606266;
  font-family: monospace;
}
.card-body {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  margin-bottom: 12px;
}
.order-meta {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
  color: #909399;
}
.item-count { color: #409eff; }
.order-price { font-size: 15px; color: #303133; }
.card-footer {
  display: flex;
  gap: 8px;
  justify-content: flex-end;
}
.pagination-wrap {
  display: flex;
  justify-content: center;
  margin-top: 24px;
}
.detail-wrap { padding: 0 4px; }
.items-title {
  margin: 16px 0 8px;
  font-size: 14px;
  font-weight: 600;
}
.item-cell {
  display: flex;
  align-items: center;
  gap: 8px;
}
.item-name { font-size: 13px; }
</style>
