<template>
  <div class="admin-layout">
    <el-container>
      <el-aside width="200px" class="aside">
        <div class="logo">ShopAdmin</div>
        <el-menu :default-active="$route.path" router>
          <el-menu-item index="/admin/dashboard">首页</el-menu-item>
          <el-menu-item index="/admin/products">商品管理</el-menu-item>
          <el-menu-item index="/admin/categories">分类管理</el-menu-item>
          <el-menu-item index="/admin/brands">品牌管理</el-menu-item>
        </el-menu>
      </el-aside>
      <el-container>
        <el-header class="header">
          <span>欢迎，{{ adminStore.adminUser?.nickname }}</span>
          <el-button type="danger" text @click="handleLogout">退出</el-button>
        </el-header>
        <el-main>
          <el-row :gutter="16">
            <el-col :span="6" v-for="card in statCards" :key="card.label">
              <el-card shadow="hover" class="stat-card">
                <div class="stat-value">{{ card.value }}</div>
                <div class="stat-label">{{ card.label }}</div>
              </el-card>
            </el-col>
          </el-row>
          <el-card style="margin-top:24px">
            <p>欢迎使用 ShopWebsite 管理后台。请从左侧菜单选择功能。</p>
          </el-card>
        </el-main>
      </el-container>
    </el-container>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAdminStore } from '@/stores/admin'
import { ElMessage } from 'element-plus'

const router     = useRouter()
const adminStore = useAdminStore()

const statCards = [
  { label: '商品管理', value: '→' },
  { label: '分类管理', value: '→' },
  { label: '品牌管理', value: '→' },
  { label: '系统状态', value: 'OK' },
]

function handleLogout() {
  adminStore.logout()
  ElMessage.success('已退出')
  router.push('/admin/login')
}
</script>

<style scoped>
.admin-layout { height: 100vh; }
.aside { background: #001529; }
.logo {
  color: #fff;
  font-size: 18px;
  font-weight: bold;
  padding: 20px;
  text-align: center;
  border-bottom: 1px solid #0d2745;
}
.aside .el-menu { border-right: none; background: #001529; }
.aside .el-menu-item { color: #a6adb4; }
.aside .el-menu-item.is-active { color: #fff; background: #1890ff; }
.header {
  background: #fff;
  border-bottom: 1px solid #e8e8e8;
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 16px;
  padding: 0 24px;
}
.stat-card { text-align: center; }
.stat-value { font-size: 28px; font-weight: bold; color: #1890ff; }
.stat-label { color: #666; margin-top: 8px; }
</style>
