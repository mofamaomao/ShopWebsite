import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  { path: '/', name: 'Home', component: () => import('@/views/HomeView.vue') },
  { path: '/login', name: 'Login', component: () => import('@/views/LoginView.vue') },
  { path: '/register', name: 'Register', component: () => import('@/views/RegisterView.vue') },
  { path: '/product/:id', name: 'Product', component: () => import('@/views/ProductView.vue') },
  { path: '/cart', name: 'Cart', meta: { requiresAuth: true }, component: () => import('@/views/CartView.vue') },
  { path: '/order-pay', name: 'OrderPay', meta: { requiresAuth: true }, component: () => import('@/views/OrderPayView.vue') },
  { path: '/order-success', name: 'OrderSuccess', meta: { requiresAuth: true }, component: () => import('@/views/OrderSuccessView.vue') },
  { path: '/order-cancelled', name: 'OrderCancelled', component: () => import('@/views/OrderCancelledView.vue') },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
})

router.beforeEach((to, from, next) => {
  if (to.meta.requiresAuth && !localStorage.getItem('token')) {
    return next('/login')
  }
  next()
})

export default router
