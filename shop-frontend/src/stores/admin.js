import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAdminStore = defineStore('admin', () => {
  const adminToken = ref(localStorage.getItem('adminToken') || '')
  const adminUser  = ref(JSON.parse(localStorage.getItem('adminUser') || 'null'))

  function login(token, user) {
    adminToken.value = token
    adminUser.value  = user
    localStorage.setItem('adminToken', token)
    localStorage.setItem('adminUser', JSON.stringify(user))
  }

  function logout() {
    adminToken.value = ''
    adminUser.value  = null
    localStorage.removeItem('adminToken')
    localStorage.removeItem('adminUser')
  }

  const isAdmin = () => adminUser.value?.role === 'ADMIN'

  return { adminToken, adminUser, login, logout, isAdmin }
})
