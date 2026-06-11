<template>
  <div class="auth-wrap">
    <div class="auth-card">
      <div class="auth-header">
        <div class="brand-circle">S</div>
        <h2 class="auth-title">欢迎回来</h2>
        <p class="auth-sub">登录 ShopDemo 继续购物</p>
      </div>
      <div class="auth-body">
        <el-form :model="form" :rules="rules" ref="formRef" label-position="top">
          <el-form-item label="手机号" prop="phone">
            <el-input v-model="form.phone" placeholder="请输入手机号" size="large" />
          </el-form-item>
          <el-form-item label="密码" prop="password">
            <el-input v-model="form.password" type="password" show-password size="large" />
          </el-form-item>
          <el-form-item style="margin-top:8px">
            <el-button type="primary" :loading="loading" @click="handleSubmit" size="large" style="width:100%">
              登录
            </el-button>
          </el-form-item>
          <div class="auth-switch">
            没有账号？<el-link type="primary" @click="$router.push('/register')">立即注册</el-link>
          </div>
        </el-form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const userStore = useUserStore()
const formRef = ref(null)
const loading = ref(false)
const form = reactive({ phone: '', password: '' })

const rules = {
  phone: [
    { required: true, message: '请输入手机号', trigger: 'blur' },
    { pattern: /^1[3-9]\d{9}$/, message: '手机号格式不正确', trigger: 'blur' },
  ],
  password: [{ required: true, min: 6, message: '密码至少6位', trigger: 'blur' }],
}

async function handleSubmit() {
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    loading.value = true
    try {
      await userStore.login(form.phone, form.password)
      ElMessage.success('登录成功')
      router.push('/')
    } catch (err) {
      ElMessage.error(err.message || '登录失败')
    } finally {
      loading.value = false
    }
  })
}
</script>

<style scoped>
.auth-wrap {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: calc(100vh - 60px);
  background: var(--color-bg-page);
}
.auth-card {
  width: 400px;
  background: #fff;
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid var(--color-border-light);
  box-shadow: 0 6px 28px oklch(0.58 0.22 353deg / 0.12);
}
.auth-header {
  background: linear-gradient(135deg, var(--color-primary) 0%, oklch(0.68 0.18 353deg) 100%);
  padding: 32px 24px 24px;
  text-align: center;
}
.brand-circle {
  width: 54px;
  height: 54px;
  background: rgba(255, 255, 255, 0.22);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  font-weight: 700;
  color: #fff;
  margin: 0 auto 12px;
}
.auth-title {
  font-size: 20px;
  font-weight: 700;
  color: #fff;
  margin-bottom: 4px;
}
.auth-sub {
  font-size: 13px;
  color: rgba(255, 255, 255, 0.8);
}
.auth-body { padding: 28px 28px 24px; }
.auth-switch {
  text-align: center;
  font-size: 13px;
  color: var(--color-subtle);
  margin-top: 4px;
}
</style>
