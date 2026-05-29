import http from './http'

export const getCart = () => http.get('/cart')
export const addToCart = (data) => http.post('/cart', data)
export const updateCartItem = (productId, quantity) => http.put(`/cart/${productId}`, { quantity })
export const removeCartItem = (productId) => http.delete(`/cart/${productId}`)
