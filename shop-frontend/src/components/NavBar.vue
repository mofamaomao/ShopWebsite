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
        <router-link to="/user/points" class="orders-link">积分中心</router-link>
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
  background: var(--color-primary);
  padding: 0 24px;
  position: sticky;
  top: 0;
  z-index: 100;
  height: 60px;
  box-shadow: 0 2px 12px oklch(0.58 0.22 353deg / 0.3);
}

.logo {
  font-size: 22px;
  font-weight: 700;
  color: #fff;
  letter-spacing: -0.3px;
}

.navbar-right {
  display: flex;
  align-items: center;
  gap: 12px;
}

.cart-link {
  color: rgba(255, 255, 255, 0.92);
  display: flex;
  align-items: center;
}

/* 购物车 badge 在彩色背景上用白底反色 */
.cart-link :deep(.el-badge__content) {
  background-color: #fff;
  color: var(--color-primary);
  border: none;
  font-weight: 700;
  font-size: 11px;
}

.username {
  color: rgba(255, 255, 255, 0.9);
  font-size: 14px;
}

.orders-link {
  font-size: 14px;
  color: rgba(255, 255, 255, 0.9);
  text-decoration: none;
  padding: 3px 6px;
  border-radius: 4px;
  transition: background 0.15s;
}
.orders-link:hover {
  color: #fff;
  background: rgba(255, 255, 255, 0.15);
}

/* 搜索框在彩色背景上 */
.navbar-center :deep(.el-input__wrapper) {
  background-color: rgba(255, 255, 255, 0.18);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.3) inset;
  border-radius: 20px;
  transition: background 0.2s, box-shadow 0.2s;
}
.navbar-center :deep(.el-input__wrapper:hover),
.navbar-center :deep(.el-input__wrapper.is-focus) {
  background-color: rgba(255, 255, 255, 0.28);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.65) inset;
}
.navbar-center :deep(.el-input__inner) {
  color: #fff;
}
.navbar-center :deep(.el-input__inner::placeholder) {
  color: rgba(255, 255, 255, 0.6);
}
.navbar-center :deep(.el-input__suffix-inner) {
  color: rgba(255, 255, 255, 0.8);
}
.navbar-center :deep(.el-input__clear) {
  color: rgba(255, 255, 255, 0.7);
}

/* 登录/注册按钮在彩色 NavBar 上反色 */
.navbar-right :deep(.el-button--primary) {
  background: #fff;
  color: var(--color-primary);
  border-color: transparent;
  font-weight: 600;
}
.navbar-right :deep(.el-button--primary:hover) {
  background: rgba(255, 255, 255, 0.9);
  border-color: transparent;
  color: var(--color-primary-hover);
}
.navbar-right :deep(.el-button--default) {
  background: transparent;
  color: #fff;
  border-color: rgba(255, 255, 255, 0.6);
}
.navbar-right :deep(.el-button--default:hover) {
  background: rgba(255, 255, 255, 0.15);
  border-color: rgba(255, 255, 255, 0.9);
  color: #fff;
}

/* 退出 text button */
.navbar-right :deep(.el-button.is-text) {
  color: rgba(255, 255, 255, 0.9);
}
.navbar-right :deep(.el-button.is-text:hover) {
  color: #fff;
  background-color: rgba(255, 255, 255, 0.15);
}
</style>
