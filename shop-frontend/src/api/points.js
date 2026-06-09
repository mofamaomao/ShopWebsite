import http from './http'

export const getPointsBalance = ()       => http.get('/user/points')
export const getPointsRecords = (params) => http.get('/user/points/records', { params })
