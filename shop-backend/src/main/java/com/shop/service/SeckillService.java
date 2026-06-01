package com.shop.service;

import com.shop.vo.SeckillVO;

public interface SeckillService {

    /** 将指定商品的秒杀库存预热到 Redis */
    void initSeckill(Long productId);

    /** 执行秒杀主流程：限流 → 扣减 Redis 库存 → 异步落库 */
    SeckillVO doSeckill(Long userId, Long productId);
}
