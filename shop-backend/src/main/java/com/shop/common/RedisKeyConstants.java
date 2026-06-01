package com.shop.common;

public final class RedisKeyConstants {

    // 秒杀剩余库存：seckill:stock:{productId}
    public static final String SECKILL_STOCK_PREFIX = "seckill:stock:";

    // 令牌桶限流：ratelimit:token:{userId}
    public static final String RATE_LIMIT_TOKEN_PREFIX = "ratelimit:token:";

    public static String seckillStockKey(Long productId) {
        return SECKILL_STOCK_PREFIX + productId;
    }

    public static String rateLimitKey(Long userId) {
        return RATE_LIMIT_TOKEN_PREFIX + userId;
    }

    private RedisKeyConstants() {}
}
