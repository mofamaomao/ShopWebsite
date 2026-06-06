import http from './http'

export const getUserOrders = (params) => http.get('/user/orders', { params })
export const getUserOrderDetail = (orderNo) => http.get(`/user/orders/${orderNo}`)
export const cancelUserOrder = (orderNo) => http.post(`/user/orders/${orderNo}/cancel`)
