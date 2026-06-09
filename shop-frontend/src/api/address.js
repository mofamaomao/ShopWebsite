import http from './http'

export const getUserAddresses  = ()        => http.get('/user/addresses')
export const createAddress     = (data)    => http.post('/user/addresses', data)
export const updateAddress     = (id, data)=> http.put(`/user/addresses/${id}`, data)
export const deleteAddress     = (id)      => http.delete(`/user/addresses/${id}`)
export const setDefaultAddress = (id)      => http.put(`/user/addresses/${id}/default`)
