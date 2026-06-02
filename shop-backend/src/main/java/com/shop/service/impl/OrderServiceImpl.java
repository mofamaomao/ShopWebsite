package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.dto.OrderCreateRequest;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.mq.OrderMessage;
import com.shop.mq.OrderProducer;
import com.shop.service.OrderService;
import com.shop.vo.OrderVO;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
public class OrderServiceImpl implements OrderService {

    private final ProductMapper productMapper;
    private final StringRedisTemplate stringRedisTemplate;
    private final OrderProducer orderProducer;

    @Autowired
    @Qualifier("orderDeductScript")
    private DefaultRedisScript<Long> orderDeductScript;

    public OrderServiceImpl(ProductMapper productMapper,
                             StringRedisTemplate stringRedisTemplate,
                             OrderProducer orderProducer) {
        this.productMapper = productMapper;
        this.stringRedisTemplate = stringRedisTemplate;
        this.orderProducer = orderProducer;
    }

    /**
     * 异步下单流程：
     *   1. 参数校验（商品存在 + 价格快照）
     *   2. Redis Lua 原子预扣库存
     *   3. 发送 OrderMessage，等待 Broker confirm（≤3s）
     *   4. confirm ack → 立即返回 orderId；nack → 回滚 Redis + 500
     *
     * Consumer 异步写 DB（order + order_item + 扣 MySQL 库存）。
     */
    @Override
    public OrderVO createOrder(Long userId, OrderCreateRequest req) {
        // Step 1: 校验商品 + 构建含价格快照的 items
        List<OrderMessage.Item> items = new ArrayList<>();
        for (OrderCreateRequest.OrderItemRequest itemReq : req.getItems()) {
            Product product = productMapper.findById(itemReq.getProductId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
            items.add(new OrderMessage.Item(product.getId(), itemReq.getQuantity(), product.getPrice()));
        }

        // Step 2: Redis 预扣库存，失败立即回滚已扣数量
        List<OrderMessage.Item> deducted = new ArrayList<>();
        try {
            for (OrderMessage.Item item : items) {
                preDeductRedisStock(item.getProductId(), item.getQuantity());
                deducted.add(item);
            }
        } catch (BusinessException e) {
            deducted.forEach(d -> rollbackRedisStock(d.getProductId(), d.getQuantity()));
            throw e;
        }

        // Step 3: 发送 MQ，等待 confirm
        String orderId = UUID.randomUUID().toString();
        OrderMessage message = new OrderMessage(orderId, userId, items, LocalDateTime.now());

        boolean ack = orderProducer.send(message);
        if (!ack) {
            items.forEach(item -> rollbackRedisStock(item.getProductId(), item.getQuantity()));
            throw new BusinessException(500, "下单失败，请重试");
        }

        // Step 4: 立即返回（DB 写入由 Consumer 异步完成）
        OrderVO vo = new OrderVO();
        vo.setOrderId(orderId);
        vo.setStatus("PROCESSING");
        log.info("[Order] created orderId={} userId={}", orderId, userId);
        return vo;
    }

    /** 懒加载：Redis key 不存在时从 DB 初始化，再执行 Lua 原子扣减 */
    private void preDeductRedisStock(Long productId, int quantity) {
        String key = RedisKeyConstants.orderStockKey(productId);

        if (!Boolean.TRUE.equals(stringRedisTemplate.hasKey(key))) {
            Product product = productMapper.findById(productId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
            // setIfAbsent 保证多线程只初始化一次
            stringRedisTemplate.opsForValue()
                    .setIfAbsent(key, String.valueOf(product.getStock()), 2, TimeUnit.HOURS);
        }

        Long result = stringRedisTemplate.execute(
                orderDeductScript,
                Collections.singletonList(key),
                String.valueOf(quantity));

        if (Long.valueOf(0L).equals(result)) {
            throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
        }
        if (!Long.valueOf(1L).equals(result)) {
            // -1: key 在 hasKey 和 execute 之间过期，降级报错
            log.warn("[Order] Redis stock key missing productId={}, retry next request", productId);
            throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
        }
    }

    private void rollbackRedisStock(Long productId, int quantity) {
        try {
            String key = RedisKeyConstants.orderStockKey(productId);
            stringRedisTemplate.opsForValue().increment(key, quantity);
            log.info("[Order] rollback Redis stock productId={} qty={}", productId, quantity);
        } catch (Exception e) {
            log.error("[Order] rollback Redis stock failed productId={}", productId, e);
        }
    }
}
