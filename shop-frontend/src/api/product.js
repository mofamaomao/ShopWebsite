import http from './http'

export const getProducts = (params) => http.get('/products', { params })
export const getProduct = (id) => http.get(`/products/${id}`)
