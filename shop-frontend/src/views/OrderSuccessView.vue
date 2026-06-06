<template>
  <div class="success-page">
    <el-result
      icon="success"
      title="支付成功！"
      :sub-title="`订单号：${orderId}　合计：¥${totalPrice}`"
    >
      <template #extra>
        <el-button type="primary" @click="$router.push('/')">继续购物</el-button>
      </template>
    </el-result>
  </div>
</template>

<script setup>
import { useRoute } from 'vue-router'

const route = useRoute()
// 兼容两种来源：
// 1. Vue Router 内部跳转（OrderPayView 轮询成功）：orderId / totalPrice
// 2. 支付宝同步跳回（sync return）：out_trade_no / total_amount
const orderId    = route.query.orderId    || route.query.out_trade_no
const totalPrice = route.query.totalPrice || route.query.total_amount
</script>

<style scoped>
.success-page {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: calc(100vh - 60px);
}
</style>
