<template>
  <div class="pay-page">
    <el-card class="pay-card">
      <template #header>
        <div class="card-header">
          <span>待支付订单</span>
          <el-tag :type="remainSeconds < 300 ? 'danger' : 'warning'" size="large">
            剩余支付时间：{{ formatTime(remainSeconds) }}
          </el-tag>
        </div>
      </template>

      <el-descriptions :column="1" border>
        <el-descriptions-item label="订单号">{{ orderId }}</el-descriptions-item>
        <el-descriptions-item label="应付金额">
          <span class="price">¥{{ totalPrice }}</span>
        </el-descriptions-item>
      </el-descriptions>

      <div class="pay-actions">
        <el-button type="primary" size="large" :loading="paying" @click="handlePay">
          立即支付（支付宝）
        </el-button>
        <el-button size="large" @click="$router.push('/')">稍后再说</el-button>
      </div>

      <el-alert v-if="pollingActive" type="info" :closable="false" style="margin-top:16px">
        支付窗口已打开，等待支付结果...
      </el-alert>

      <el-alert type="warning" :closable="false" style="margin-top:16px" show-icon>
        订单已创建，商品库存已锁定。请在 <strong>{{ formatTime(remainSeconds) }}</strong> 内完成支付，超时订单将自动取消并恢复库存。
      </el-alert>
    </el-card>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getOrderStatus, createPay, queryPayStatus } from '@/api/order'

const route  = useRoute()
const router = useRouter()

const orderId      = route.query.orderId
const totalPrice   = route.query.totalPrice
const paying       = ref(false)
const pollingActive = ref(false)
const remainSeconds = ref(1800)

// ── 倒计时 ────────────────────────────────────────────────────────────
const countdownTimer = setInterval(() => {
  remainSeconds.value--
  if (remainSeconds.value <= 0) {
    stop()
    router.push('/order-cancelled')
  }
}, 1000)

// ── 订单状态轮询（检测超时取消 / 已PAID） ─────────────────────────────
const statusTimer = setInterval(async () => {
  try {
    const data = await getOrderStatus(orderId)
    if (data.remainSeconds !== undefined) remainSeconds.value = data.remainSeconds
    if (data.status === 'CANCELLED') { stop(); router.push('/order-cancelled') }
    else if (data.status === 'PAID')  { stop(); router.push({ path: '/order-success', query: { orderId, totalPrice } }) }
  } catch {}
}, 5000)

// ── 支付结果轮询（发起支付后启动，每 3 秒查询支付宝） ──────────────────
let pollingTimer = null

function startPolling() {
  pollingActive.value = true
  pollingTimer = setInterval(async () => {
    try {
      const data = await queryPayStatus(orderId)
      if (data.status === 'TRADE_SUCCESS') {
        stop()
        router.push({ path: '/order-success', query: { orderId, totalPrice } })
      }
    } catch {}
  }, 3000)
}

function stop() {
  clearInterval(countdownTimer)
  clearInterval(statusTimer)
  clearInterval(pollingTimer)
  pollingActive.value = false
}

onMounted(async () => {
  try {
    const data = await getOrderStatus(orderId)
    if (data.remainSeconds > 0) remainSeconds.value = data.remainSeconds
    if (data.status === 'CANCELLED') { stop(); router.push('/order-cancelled') }
    else if (data.status === 'PAID')  { stop(); router.push({ path: '/order-success', query: { orderId, totalPrice } }) }
  } catch {}
})

onUnmounted(() => stop())

function formatTime(s) {
  const m   = Math.floor(s / 60).toString().padStart(2, '0')
  const sec = (s % 60).toString().padStart(2, '0')
  return `${m}:${sec}`
}

async function handlePay() {
  paying.value = true
  try {
    const data = await createPay({ orderId })
    // 在新窗口打开支付宝收银台表单
    const win = window.open('', '_blank')
    if (!win) {
      ElMessage.warning('弹窗被拦截，请允许弹窗后重试')
      return
    }
    win.document.write(data.payForm)
    win.document.close()
    // 启动支付结果轮询
    startPolling()
  } catch (err) {
    ElMessage.error(err.message || '支付发起失败')
  } finally {
    paying.value = false
  }
}
</script>

<style scoped>
.pay-page {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: calc(100vh - 60px);
  padding: 24px;
}
.pay-card { width: 480px; }
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.price { color: #f56c6c; font-size: 24px; font-weight: bold; }
.pay-actions {
  display: flex;
  gap: 16px;
  justify-content: center;
  margin-top: 32px;
}
</style>
