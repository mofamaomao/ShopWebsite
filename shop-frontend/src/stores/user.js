import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { login as loginApi, register as registerApi } from '@/api/auth'

export const useUserStore = defineStore('user', () => {
  const token = ref(localStorage.getItem('token') || '')
  const nickname = ref(localStorage.getItem('nickname') || '')

  const isLoggedIn = computed(() => !!token.value)

  async function login(phone, password) {
    const data = await loginApi({ phone, password })
    token.value = data.token
    localStorage.setItem('token', data.token)
  }

  async function register(phone, password, nicknameVal) {
    await registerApi({ phone, password, nickname: nicknameVal })
  }

  function logout() {
    token.value = ''
    nickname.value = ''
    localStorage.removeItem('token')
    localStorage.removeItem('nickname')
  }

  return { token, nickname, isLoggedIn, login, register, logout }
})
