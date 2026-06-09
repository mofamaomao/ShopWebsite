<template>
  <el-header class="navbar">
    <div class="navbar-left">
      <router-link to="/" class="logo">ShopDemo</router-link>
    </div>
    <div class="navbar-center">
      <el-input
        v-model="keyword"
        placeholder="搜索商品..."
        clearable
        @keyup.enter="handleSearch"
        style="width: 300px"
      >
        <template #suffix>
          <el-icon style="cursor:pointer" @click="handleSearch"><Search /></el-icon>
        </template>
      </el-input>
    </div>
    <div class="navbar-right">
      <router-link to="/cart" class="cart-link">
        <el-badge :value="cartStore.cartCount" :hidden="cartStore.cartCount === 0">
          <el-icon size="24"><ShoppingCart /></el-icon>
        </el-badge>
      </router-link>
      <template v-if="userStore.isLoggedIn">
        <router-link to="/user/orders" class="orders-link">我的订单</router-link>
        <router-link to="/user/addresses" class="orders-link">地址管理</router-link>
        <span class="username">{{ userStore.nickname || '用户' }}</span>
        <el-button text @click="handleLogout">退出</el-button>
      </template>
      <template v-else>
        <router-link to="/login">
          <el-button type="primary" size="small">登录</el-button>
        </router-link>
        <router-link to="/register">
          <el-button size="small">注册</el-button>
        </router-link>
      </template>
    </div>
  </el-header>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Search, ShoppingCart } from '@element-plus/icons-vue'
import { useUserStore } from '@/stores/user'
import { useCartStore } from '@/stores/cart'

const router = useRouter()
const userStore = useUserStore()
const cartStore = useCartStore()
const keyword = ref('')

onMounted(() => {
  if (userStore.isLoggedIn) cartStore.fetchCount()
})

function handleSearch() {
  router.push({ path: '/', query: keyword.value ? { keyword: keyword.value } : {} })
}

function handleLogout() {
  userStore.logout()
  router.push('/login')
}
</script>

<style scoped>
.navbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #eee;
  padding: 0 24px;
  position: sticky;
  top: 0;
  z-index: 100;
  height: 60px;
}
.logo {
  font-size: 22px;
  font-weight: bold;
  color: #409eff;
}
.navbar-right {
  display: flex;
  align-items: center;
  gap: 12px;
}
.cart-link {
  color: #606266;
  display: flex;
  align-items: center;
}
.username {
  color: #606266;
  font-size: 14px;
}
.orders-link {
  font-size: 14px;
  color: #606266;
  text-decoration: none;
}
.orders-link:hover {
  color: #409eff;
}
</style>
