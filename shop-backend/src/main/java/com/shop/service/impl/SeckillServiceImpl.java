package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.service.SeckillAsyncService;
import com.shop.service.SeckillCacheService;
import com.shop.service.SeckillService;
import com.shop.vo.SeckillVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class SeckillServiceImpl implements SeckillService {

    private final SeckillCacheService seckillCacheService;
    private final SeckillAsyncService seckillAsyncService;

    @Override
    public void initSeckill(Long productId) {
        seckillCacheService.initStock(productId);
    }

    @Override
    public SeckillVO doSeckill(Long userId, Long productId) {
        // Step 1: 令牌桶限流
        if (!seckillCacheService.checkRateLimit(userId)) {
            throw new BusinessException(429, "请求过于频繁，请稍后再试");
        }

        // Step 2: Lua 原子扣减 Redis 库存
        if (!seckillCacheService.deductStock(productId)) {
            throw new BusinessException(ErrorCode.SECKILL_STOCK_EMPTY);
        }

        // Step 3: 异步写订单到 DB（不阻塞响应）
        seckillAsyncService.writeOrderAsync(userId, productId);

        log.info("秒杀成功 userId={} productId={}", userId, productId);

        // Step 4: 返回占位订单号（真实 orderId 由异步线程落库后生成）
        SeckillVO vo = new SeckillVO();
        vo.setOrderId("SK-" + productId + "-" + userId + "-" + System.currentTimeMillis());
        return vo;
    }
}
