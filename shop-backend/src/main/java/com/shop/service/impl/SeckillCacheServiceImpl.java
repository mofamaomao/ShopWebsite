package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.mapper.ProductMapper;
import com.shop.service.SeckillCacheService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
public class SeckillCacheServiceImpl implements SeckillCacheService {

    private static final int TOKEN_CAPACITY    = 5;
    private static final int TOKEN_REFILL_RATE = 2;
    private static final int TOKEN_TTL_SECONDS = 60;

    private final StringRedisTemplate redisTemplate;
    private final ProductMapper productMapper;
    private final DefaultRedisScript<Long> seckillDeductScript;
    private final DefaultRedisScript<Long> tokenBucketScript;

    public SeckillCacheServiceImpl(
            StringRedisTemplate redisTemplate,
            ProductMapper productMapper,
            @Qualifier("seckillDeductScript") DefaultRedisScript<Long> seckillDeductScript,
            @Qualifier("tokenBucketScript")   DefaultRedisScript<Long> tokenBucketScript) {
        this.redisTemplate       = redisTemplate;
        this.productMapper       = productMapper;
        this.seckillDeductScript = seckillDeductScript;
        this.tokenBucketScript   = tokenBucketScript;
    }

    @Override
    public void initStock(Long productId) {
        Integer stock = productMapper.findSeckillStockById(productId);
        if (stock == null) {
            throw new BusinessException(ErrorCode.PRODUCT_NOT_FOUND);
        }
        String key = RedisKeyConstants.seckillStockKey(productId);
        redisTemplate.opsForValue().set(key, String.valueOf(stock), 1, TimeUnit.HOURS);
        log.info("秒杀库存预热完成 productId={} stock={}", productId, stock);
    }

    @Override
    public boolean deductStock(Long productId) {
        String key = RedisKeyConstants.seckillStockKey(productId);
        try {
            Long result = redisTemplate.execute(
                    seckillDeductScript,
                    Collections.singletonList(key));
            return Long.valueOf(1L).equals(result);
        } catch (Exception e) {
            log.error("Redis 扣减库存失败 productId={}", productId, e);
            throw new RuntimeException("Redis 操作失败", e);
        }
    }

    @Override
    public boolean checkRateLimit(Long userId) {
        String key = RedisKeyConstants.rateLimitKey(userId);
        try {
            Long result = redisTemplate.execute(
                    tokenBucketScript,
                    Collections.singletonList(key),
                    String.valueOf(System.currentTimeMillis()),
                    String.valueOf(TOKEN_CAPACITY),
                    String.valueOf(TOKEN_REFILL_RATE),
                    String.valueOf(TOKEN_TTL_SECONDS));
            return Long.valueOf(1L).equals(result);
        } catch (Exception e) {
            log.error("Redis 限流检查失败 userId={}", userId, e);
            throw new RuntimeException("Redis 操作失败", e);
        }
    }
}
