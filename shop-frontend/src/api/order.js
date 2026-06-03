import http from './http'

export const createOrder   = (data)    => http.post('/orders', data)
export const getOrderStatus = (orderId) => http.get(`/orders/${orderId}/status`)
export const payOrder      = (orderId) => http.post(`/orders/${orderId}/pay`)
