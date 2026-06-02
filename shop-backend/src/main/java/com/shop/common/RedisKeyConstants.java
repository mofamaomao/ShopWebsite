package com.shop.common;

public final class RedisKeyConstants {

    // 秒杀剩余库存：seckill:stock:{productId}
    public static final String SECKILL_STOCK_PREFIX = "seckill:stock:";

    // 令牌桶限流：ratelimit:token:{userId}
    public static final String RATE_LIMIT_TOKEN_PREFIX = "ratelimit:token:";

    // 普通下单分布式锁：order:lock:{userId}
    public static final String ORDER_LOCK = "order:lock:";

    // 商品详情缓存：product:detail:{id}
    public static final String PRODUCT_DETAIL_PREFIX = "product:detail:";

    // 商品缓存重建互斥锁：lock:product:{id}
    public static final String PRODUCT_LOCK_PREFIX = "lock:product:";

    // 布隆过滤器 key
    public static final String PRODUCT_BLOOM_FILTER = "product:bloom";

    public static String productDetailKey(Long id) {
        return PRODUCT_DETAIL_PREFIX + id;
    }

    public static String productLockKey(Long id) {
        return PRODUCT_LOCK_PREFIX + id;
    }

    public static String seckillStockKey(Long productId) {
        return SECKILL_STOCK_PREFIX + productId;
    }

    public static String rateLimitKey(Long userId) {
        return RATE_LIMIT_TOKEN_PREFIX + userId;
    }

    private RedisKeyConstants() {}
}
