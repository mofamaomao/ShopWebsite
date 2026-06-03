import axios from 'axios'
import router from '@/router'

const adminHttp = axios.create({
  baseURL: import.meta.env.VITE_API_PREFIX || '/api',
  timeout: 10000,
  headers: { 'Content-Type': 'application/json' },
})

adminHttp.interceptors.request.use((config) => {
  const token = localStorage.getItem('adminToken')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

adminHttp.interceptors.response.use(
  (response) => {
    const res = response.data
    if (res.code !== 200) return Promise.reject(new Error(res.msg || '请求失败'))
    return res.data
  },
  (error) => {
    if (error.response?.status === 401 || error.response?.status === 403) {
      localStorage.removeItem('adminToken')
      router.push('/admin/login')
    }
    return Promise.reject(error)
  }
)

export default adminHttp

// ── 分类 ──────────────────────────────────────────────────────────────
export const getCategoryTree    = ()           => adminHttp.get('/admin/categories')
export const createCategory     = (data)       => adminHttp.post('/admin/categories', data)
export const updateCategory     = (id, data)   => adminHttp.put(`/admin/categories/${id}`, data)
export const deleteCategory     = (id)         => adminHttp.delete(`/admin/categories/${id}`)

// ── 品牌 ──────────────────────────────────────────────────────────────
export const getAllBrands        = ()           => adminHttp.get('/admin/brands/all')
export const getBrands          = (params)     => adminHttp.get('/admin/brands', { params })
export const createBrand        = (data)       => adminHttp.post('/admin/brands', data)
export const updateBrand        = (id, data)   => adminHttp.put(`/admin/brands/${id}`, data)
export const deleteBrand        = (id)         => adminHttp.delete(`/admin/brands/${id}`)

// ── 商品 ──────────────────────────────────────────────────────────────
export const getAdminProducts   = (params)     => adminHttp.get('/admin/products', { params })
export const createAdminProduct = (data)       => adminHttp.post('/admin/products', data)
export const updateAdminProduct = (id, data)   => adminHttp.put(`/admin/products/${id}`, data)
export const deleteAdminProduct = (id)         => adminHttp.delete(`/admin/products/${id}`)
export const toggleProductStatus = (id, status) => adminHttp.put(`/admin/products/${id}/status`, null, { params: { status } })
