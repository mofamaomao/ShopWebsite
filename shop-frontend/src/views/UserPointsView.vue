<template>
  <div class="points-page">
    <!-- 顶部余额卡片 -->
    <div class="balance-card">
      <div class="balance-label">我的积分</div>
      <div class="balance-number">{{ displayBalance }}</div>
      <div class="balance-sub" v-if="info">
        可抵扣 ¥{{ deductibleAmount }} &nbsp;·&nbsp;
        累计获得 {{ info.totalEarned }} &nbsp;·&nbsp;
        已使用 {{ info.totalUsed }}
      </div>
    </div>

    <!-- 明细列表 -->
    <el-card shadow="never" class="records-card">
      <template #header><span class="records-title">积分明细</span></template>
      <div v-loading="loading">
        <el-table :data="records" size="small" empty-text="暂无积分记录">
          <el-table-column label="时间" width="180">
            <template #default="{ row }">{{ formatDate(row.createdAt) }}</template>
          </el-table-column>
          <el-table-column prop="source" label="来源" />
          <el-table-column label="积分变动" width="120" align="right">
            <template #default="{ row }">
              <span :class="row.points > 0 ? 'earn' : 'cost'">
                {{ row.points > 0 ? '+' : '' }}{{ row.points }}
              </span>
            </template>
          </el-table-column>
          <el-table-column label="余额" prop="balance" width="100" align="right" />
        </el-table>

        <div class="pagination-wrap">
          <el-pagination
            v-model:current-page="page"
            v-model:page-size="size"
            :page-sizes="[10, 20, 50]"
            :total="total"
            layout="total, sizes, prev, pager, next"
            @size-change="loadRecords"
            @current-change="loadRecords"
          />
        </div>
      </div>
    </el-card>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { getPointsBalance, getPointsRecords } from '@/api/points'

const info           = ref(null)
const displayBalance = ref(0)
const records        = ref([])
const total          = ref(0)
const page           = ref(1)
const size           = ref(20)
const loading        = ref(false)

const deductibleAmount = computed(() => {
  if (!info.value) return '0.00'
  return (info.value.balance / info.value.redeemRate).toFixed(2)
})

onMounted(async () => {
  const data = await getPointsBalance()
  info.value = data
  animateBalance(data.balance)
  await loadRecords()
})

async function loadRecords() {
  loading.value = true
  try {
    const res = await getPointsRecords({ page: page.value, size: size.value })
    records.value = res.list
    total.value   = res.total
  } finally {
    loading.value = false
  }
}

function animateBalance(target) {
  if (target === 0) return
  const duration = 900
  const startTime = performance.now()
  function step(now) {
    const progress = Math.min((now - startTime) / duration, 1)
    const eased = 1 - Math.pow(1 - progress, 3)
    displayBalance.value = Math.round(target * eased)
    if (progress < 1) requestAnimationFrame(step)
    else displayBalance.value = target
  }
  requestAnimationFrame(step)
}

function formatDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleString('zh-CN', { hour12: false })
}
</script>

<style scoped>
.points-page {
  max-width: 820px;
  margin: 32px auto;
  padding: 0 16px;
}
.balance-card {
  background: linear-gradient(135deg, var(--color-primary) 0%, oklch(0.70 0.16 353deg) 100%);
  border-radius: 12px;
  padding: 32px 40px;
  color: #fff;
  margin-bottom: 24px;
  text-align: center;
}
.balance-label {
  font-size: 15px;
  opacity: 0.85;
  margin-bottom: 8px;
}
.balance-number {
  font-size: 64px;
  font-weight: 700;
  letter-spacing: -2px;
  line-height: 1;
  margin-bottom: 12px;
}
.balance-sub {
  font-size: 13px;
  opacity: 0.8;
}
.records-card { border-radius: 8px; }
.records-title { font-size: 15px; font-weight: 600; }
.earn { color: #67c23a; font-weight: 600; }
.cost { color: #f56c6c; font-weight: 600; }
.pagination-wrap {
  display: flex;
  justify-content: center;
  margin-top: 20px;
}
</style>
