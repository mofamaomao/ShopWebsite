import http from './http'

export const getCart = () => http.get('/cart')
export const addToCart = (data) => http.post('/cart', data)
