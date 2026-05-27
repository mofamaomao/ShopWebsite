import { defineStore } from 'pinia'
import { ref } from 'vue'
import http from '@/api/http'

export const useUserStore = defineStore('user', () => {
  const token = ref(localStorage.getItem('token') || '')
  const userInfo = ref(null)

  function setToken(newToken) {
    token.value = newToken
    localStorage.setItem('token', newToken)
  }

  function logout() {
    token.value = ''
    userInfo.value = null
    localStorage.removeItem('token')
  }

  async function fetchUserInfo() {
    const data = await http.get('/user/me')
    userInfo.value = data
  }

  return { token, userInfo, setToken, logout, fetchUserInfo }
})
