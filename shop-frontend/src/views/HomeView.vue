<template>
  <div class="home">
    <el-container>
      <el-header>
        <div class="header-content">
          <span class="logo">ShopDemo</span>
          <el-button type="danger" text @click="handleLogout">退出登录</el-button>
        </div>
      </el-header>
      <el-main>
        <el-result icon="success" title="后端连接成功" :sub-title="`健康检查: ${healthStatus}`" />
      </el-main>
    </el-container>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import http from '@/api/http'

const router = useRouter()
const userStore = useUserStore()
const healthStatus = ref('checking...')

onMounted(async () => {
  try {
    const res = await http.get('/health')
    healthStatus.value = res
  } catch {
    healthStatus.value = 'unreachable'
  }
})

function handleLogout() {
  userStore.logout()
  router.push('/login')
}
</script>

<style scoped>
.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  height: 100%;
}
.logo {
  font-size: 20px;
  font-weight: bold;
}
</style>
