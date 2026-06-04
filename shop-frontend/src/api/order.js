import http from './http'

export const createOrder    = (data)    => http.post('/orders', data)
export const getOrderStatus = (orderId) => http.get(`/orders/${orderId}/status`)
export const payOrder       = (orderId) => http.post(`/orders/${orderId}/pay`)  // 模拟支付（兼容保留）

// 支付宝真实支付
export const createPay      = (data)    => http.post('/pay/create', data)
export const queryPayStatus = (orderId) => http.get(`/pay/query/${orderId}`)
