<template>
  <div class="admin-login">
    <el-card class="login-card">
      <template #header>
        <h2>管理后台登录</h2>
      </template>
      <el-form :model="form" :rules="rules" ref="formRef" label-width="80px">
        <el-form-item label="账号" prop="phone">
          <el-input v-model="form.phone" placeholder="请输入管理员账号" />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input v-model="form.password" type="password" placeholder="请输入密码" show-password />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="loading" @click="handleLogin" style="width:100%">
            登录
          </el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import http from '@/api/http'
import { useAdminStore } from '@/stores/admin'

const router    = useRouter()
const adminStore = useAdminStore()
const formRef   = ref(null)
const loading   = ref(false)

const form = ref({ phone: '', password: '' })
const rules = {
  phone:    [{ required: true, message: '账号不能为空', trigger: 'blur' }],
  password: [{ required: true, message: '密码不能为空', trigger: 'blur' }],
}

async function handleLogin() {
  await formRef.value.validate()
  loading.value = true
  try {
    const data = await http.post('/auth/login', form.value)
    if (data.user?.role !== 'ADMIN') {
      ElMessage.error('无管理员权限')
      return
    }
    adminStore.login(data.token, data.user)
    ElMessage.success('登录成功')
    router.push('/admin/dashboard')
  } catch (err) {
    ElMessage.error(err.message || '登录失败')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.admin-login {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  background: #f0f2f5;
}
.login-card {
  width: 400px;
}
.login-card h2 {
  text-align: center;
  margin: 0;
}
</style>
