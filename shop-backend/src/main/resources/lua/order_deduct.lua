-- order_deduct.lua
-- 原子扣减普通订单库存（支持任意数量）
-- KEYS[1] = order:stock:{productId}
-- ARGV[1] = quantity
-- 返回：1=成功，0=库存不足，-1=key 不存在（需调用方初始化）

local stock = redis.call('GET', KEYS[1])
if not stock then
    return -1
end
local s = tonumber(stock)
local q = tonumber(ARGV[1])
if s < q then
    return 0
end
redis.call('DECRBY', KEYS[1], q)
return 1
