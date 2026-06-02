package com.shop.util;

import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;

@Component
@RequiredArgsConstructor
public class CacheUtil {

    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * 写缓存时叠加随机抖动（0~300s），防止缓存雪崩——大量 key 同时到期。
     */
    public void setWithRandomTTL(String key, Object value, long baseTTL, TimeUnit unit) {
        long jitter = ThreadLocalRandom.current().nextLong(0, 300);
        redisTemplate.opsForValue().set(key, value, baseTTL + jitter, unit);
    }
}
