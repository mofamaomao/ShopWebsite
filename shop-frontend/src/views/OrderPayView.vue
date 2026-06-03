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
          立即支付
        </el-button>
        <el-button size="large" @click="$router.push('/')">稍后再说</el-button>
      </div>
    </el-card>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getOrderStatus, payOrder } from '@/api/order'

const route  = useRoute()
const router = useRouter()

const orderId    = route.query.orderId
const totalPrice = route.query.totalPrice   // Bug1 fix: 来自下单接口预计算值
const paying     = ref(false)
const remainSeconds = ref(1800)

// ── 倒计时，每秒 -1 ───────────────────────────────────────────────────
const countdownTimer = setInterval(() => {
  remainSeconds.value--
  if (remainSeconds.value <= 0) {
    clearInterval(countdownTimer)
    router.push('/order-cancelled')
  }
}, 1000)

// ── 每 5 秒轮询订单状态（检测 MQ 超时取消）────────────────────────────
const pollTimer = setInterval(async () => {
  try {
    const data = await getOrderStatus(orderId)
    if (data.remainSeconds !== undefined) remainSeconds.value = data.remainSeconds
    if (data.status === 'CANCELLED') {
      stop()
      router.push('/order-cancelled')
    } else if (data.status === 'PAID') {
      stop()
      router.push({ path: '/order-success', query: { orderId, totalPrice } })
    }
  } catch {}
}, 5000)

function stop() {
  clearInterval(countdownTimer)
  clearInterval(pollTimer)
}

onMounted(async () => {
  // 首次同步服务端剩余秒数（Consumer 落库后才有准确值）
  try {
    const data = await getOrderStatus(orderId)
    if (data.remainSeconds > 0) remainSeconds.value = data.remainSeconds
    if (data.status === 'CANCELLED') { stop(); router.push('/order-cancelled') }
  } catch {}
})

onUnmounted(() => stop())   // 离开页面必须清除定时器，防止内存泄漏

function formatTime(s) {
  const m = Math.floor(s / 60).toString().padStart(2, '0')
  const sec = (s % 60).toString().padStart(2, '0')
  return `${m}:${sec}`
}

async function handlePay() {
  paying.value = true
  try {
    await payOrder(orderId)
    stop()
    ElMessage.success('支付成功！')
    router.push({ path: '/order-success', query: { orderId, totalPrice } })
  } catch (err) {
    ElMessage.error(err.message || '支付失败')
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
