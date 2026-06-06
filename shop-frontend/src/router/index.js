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
  { path: '/user/orders', name: 'UserOrders', meta: { requiresAuth: true }, component: () => import('@/views/UserOrdersView.vue') },

  // 管理后台
  { path: '/admin/login', name: 'AdminLogin', component: () => import('@/views/admin/AdminLoginView.vue') },
  {
    path: '/admin',
    meta: { requiresAdmin: true },
    children: [
      { path: 'dashboard', name: 'AdminDashboard', component: () => import('@/views/admin/AdminDashboardView.vue') },
      { path: 'products', name: 'AdminProducts', component: () => import('@/views/admin/AdminProductsView.vue') },
      { path: 'products/add', name: 'AdminProductAdd', component: () => import('@/views/admin/AdminProductFormView.vue') },
      { path: 'products/:id/edit', name: 'AdminProductEdit', component: () => import('@/views/admin/AdminProductFormView.vue') },
      { path: 'categories', name: 'AdminCategories', component: () => import('@/views/admin/AdminCategoriesView.vue') },
      { path: 'brands', name: 'AdminBrands', component: () => import('@/views/admin/AdminBrandsView.vue') },
    ],
  },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
})

router.beforeEach((to, from, next) => {
  if (to.meta.requiresAuth && !localStorage.getItem('token')) {
    return next('/login')
  }
  if (to.meta.requiresAdmin) {
    const user = JSON.parse(localStorage.getItem('adminUser') || 'null')
    if (!localStorage.getItem('adminToken') || user?.role !== 'ADMIN') {
      return next('/admin/login')
    }
  }
  next()
})

export default router
