import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    path: '/',
    name: 'Home',
    component: () => import('@/views/HomeView.vue'),
  },
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/LoginView.vue'),
  },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
})

// 路由守卫：需要登录的页面检查 token
router.beforeEach((to, from, next) => {
  const publicPages = ['/login']
  const requiresAuth = !publicPages.includes(to.path)
  const token = localStorage.getItem('token')
  if (requiresAuth && !token) {
    return next('/login')
  }
  next()
})

export default router
