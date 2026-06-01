-- seckill_deduct.lua
-- 原子扣减秒杀库存，防止并发超卖
-- KEYS[1] = seckill:stock:{productId}
-- 返回 1 = 扣减成功，0 = 库存不足

local stock = redis.call('GET', KEYS[1])
if not stock or tonumber(stock) <= 0 then
    return 0
end
redis.call('DECRBY', KEYS[1], 1)
return 1
