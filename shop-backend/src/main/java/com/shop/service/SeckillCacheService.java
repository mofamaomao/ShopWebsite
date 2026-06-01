package com.shop.service;

public interface SeckillCacheService {

    /** 将 DB 中的 seckill_stock 预热到 Redis，TTL 1 小时 */
    void initStock(Long productId);

    /** Lua 原子扣减库存，成功返回 true，库存不足返回 false */
    boolean deductStock(Long productId);

    /** 令牌桶限流检查，允许返回 true，超限返回 false */
    boolean checkRateLimit(Long userId);
}
