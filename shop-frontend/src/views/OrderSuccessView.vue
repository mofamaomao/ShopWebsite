<template>
  <div class="success-page">
    <el-result
      icon="success"
      title="下单成功！"
      :sub-title="`订单号：${orderId}　合计：¥${total}`"
    >
      <template #extra>
        <el-button type="primary" @click="$router.push('/')">继续购物</el-button>
        <el-button @click="$router.push('/cart')">查看购物车</el-button>
      </template>
    </el-result>
  </div>
</template>

<script setup>
import { useRoute } from 'vue-router'

const route = useRoute()
const orderId = route.query.orderId
const total = route.query.total
</script>

<style scoped>
.success-page {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: calc(100vh - 60px);
}
</style>
