-- token_bucket.lua
-- 令牌桶限流：读取 / 补充 / 消费令牌，原子执行
-- KEYS[1]  = ratelimit:token:{userId}
-- ARGV[1]  = 当前时间戳（毫秒）
-- ARGV[2]  = 桶容量（最大令牌数）
-- ARGV[3]  = 补充速率（令牌/秒）
-- ARGV[4]  = key TTL（秒）
-- 返回 1 = 允许，0 = 超限

local key       = KEYS[1]
local now       = tonumber(ARGV[1])
local capacity  = tonumber(ARGV[2])
local rate      = tonumber(ARGV[3])
local ttl       = tonumber(ARGV[4])

local data      = redis.call('HMGET', key, 'tokens', 'lastRefill')
local tokens    = tonumber(data[1])
local lastRefill = tonumber(data[2])

if tokens == nil then
    -- 首次请求：初始化桶，消费一个令牌后存入
    redis.call('HMSET', key, 'tokens', capacity - 1, 'lastRefill', now)
    redis.call('EXPIRE', key, ttl)
    return 1
end

-- 按流逝时间补充令牌
local elapsed = (now - lastRefill) / 1000
local added   = math.floor(elapsed * rate)
tokens = math.min(capacity, tokens + added)
if added > 0 then
    lastRefill = now
end

if tokens < 1 then
    -- 令牌耗尽，更新状态后拒绝
    redis.call('HMSET', key, 'tokens', 0, 'lastRefill', lastRefill)
    redis.call('EXPIRE', key, ttl)
    return 0
end

-- 消费一个令牌
redis.call('HMSET', key, 'tokens', tokens - 1, 'lastRefill', lastRefill)
redis.call('EXPIRE', key, ttl)
return 1
