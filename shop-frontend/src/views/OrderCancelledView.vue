<template>
  <div class="cancelled-page">
    <el-result
      icon="warning"
      title="订单已取消"
      sub-title="订单因超时未支付或已手动取消，占用的库存已自动释放。"
    >
      <template #extra>
        <el-button type="primary" @click="$router.push('/')">重新购物</el-button>
        <el-button @click="$router.push('/cart')">查看购物车</el-button>
      </template>
    </el-result>
  </div>
</template>

<style scoped>
.cancelled-page {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: calc(100vh - 60px);
}
</style>
