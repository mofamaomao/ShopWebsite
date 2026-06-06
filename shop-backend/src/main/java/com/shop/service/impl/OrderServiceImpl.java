package com.shop.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.dto.OrderCreateRequest;
import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.entity.Product;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.ProductMapper;
import com.shop.mq.OrderMessage;
import com.shop.mq.OrderProducer;
import com.shop.service.CartService;
import com.shop.service.MqMessageService;
import com.shop.service.OrderService;
import com.shop.vo.OrderStatusVO;
import com.shop.vo.OrderVO;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
public class OrderServiceImpl implements OrderService {

    private final ProductMapper       productMapper;
    private final OrderMapper         orderMapper;
    private final OrderItemMapper     orderItemMapper;
    private final StringRedisTemplate stringRedisTemplate;
    private final OrderProducer       orderProducer;
    private final MqMessageService    mqMessageService;
    private final CartService         cartService;
    private final ObjectMapper        objectMapper;

    @Autowired
    @Qualifier("orderDeductScript")
    private DefaultRedisScript<Long> orderDeductScript;

    public OrderServiceImpl(ProductMapper productMapper,
                            OrderMapper orderMapper,
                            OrderItemMapper orderItemMapper,
                            StringRedisTemplate stringRedisTemplate,
                            OrderProducer orderProducer,
                            MqMessageService mqMessageService,
                            CartService cartService,
                            ObjectMapper objectMapper) {
        this.productMapper       = productMapper;
        this.orderMapper         = orderMapper;
        this.orderItemMapper     = orderItemMapper;
        this.stringRedisTemplate = stringRedisTemplate;
        this.orderProducer       = orderProducer;
        this.mqMessageService    = mqMessageService;
        this.cartService         = cartService;
        this.objectMapper        = objectMapper;
    }

    /**
     * 异步下单：
     *   1. 参数校验 + 价格快照
     *   2. Redis Lua 原子预扣库存
     *   3. 写 mq_message 表（status=0），失败回滚 Redis
     *   4. 发送 MQ，confirm 回调异步更新 status=1/2
     *   5. 立即返回 PROCESSING
     */
    @Override
    public OrderVO createOrder(Long userId, OrderCreateRequest req) {
        // Step 1: 校验商品 + 构建含价格快照的 items
        List<OrderMessage.Item> items = new ArrayList<>();
        for (OrderCreateRequest.OrderItemRequest itemReq : req.getItems()) {
            Product product = productMapper.findById(itemReq.getProductId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
            items.add(new OrderMessage.Item(
                    product.getId(), itemReq.getQuantity(), product.getPrice(),
                    product.getName(),
                    product.getImageUrl() != null ? product.getImageUrl() : ""));
        }
        // Bug1 fix: 在 Producer 端预计算 totalPrice，不依赖 Consumer 写库
        BigDecimal totalPrice = items.stream()
                .map(i -> i.getPrice().multiply(BigDecimal.valueOf(i.getQuantity())))
                .reduce(BigDecimal.ZERO, BigDecimal::add);

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

        // Step 3: 写 mq_message 表（status=0），失败回滚 Redis
        String orderId = UUID.randomUUID().toString();
        OrderMessage message = new OrderMessage(orderId, userId, items, LocalDateTime.now());
        try {
            String content = objectMapper.writeValueAsString(message);
            mqMessageService.save(orderId, content);
        } catch (JsonProcessingException | RuntimeException e) {
            deducted.forEach(d -> rollbackRedisStock(d.getProductId(), d.getQuantity()));
            throw new BusinessException(500, "下单失败，请重试");
        }

        // Step 4: 异步发送 MQ（confirm 回调更新 mq_message status）
        orderProducer.send(message);

        // Bug2 fix: MQ 消息发出后清空购物车（Redis Hash + 前端 Pinia 各自负责）
        cartService.clearCart(userId);

        // Step 5: 立即返回（DB 写入由 Consumer 异步完成）
        OrderVO vo = new OrderVO();
        vo.setOrderId(orderId);
        vo.setTotalPrice(totalPrice);      // Bug1 fix: 返回预计算的金额
        vo.setStatus("PENDING_PAYMENT");
        log.info("[Order] created orderId={} userId={} total={}", orderId, userId, totalPrice);
        return vo;
    }

    private void preDeductRedisStock(Long productId, int quantity) {
        String key = RedisKeyConstants.orderStockKey(productId);
        if (!Boolean.TRUE.equals(stringRedisTemplate.hasKey(key))) {
            Product product = productMapper.findById(productId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
            stringRedisTemplate.opsForValue()
                    .setIfAbsent(key, String.valueOf(product.getStock()), 2, TimeUnit.HOURS);
        }
        Long result = stringRedisTemplate.execute(
                orderDeductScript, Collections.singletonList(key), String.valueOf(quantity));
        if (Long.valueOf(0L).equals(result)) {
            throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
        }
        if (!Long.valueOf(1L).equals(result)) {
            log.warn("[Order] Redis stock key missing productId={}", productId);
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

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void cancelOrder(String orderNo) {
        Order order = orderMapper.findByOrderNo(orderNo).orElse(null);
        if (order == null) {
            log.warn("[Cancel] order not found orderNo={}", orderNo);
            return;
        }
        if (!"PENDING_PAYMENT".equals(order.getStatus())) {
            log.info("[Cancel] skip, status={} orderNo={}", order.getStatus(), orderNo);
            return;
        }

        Order update = new Order();
        update.setId(order.getId());
        update.setStatus("CANCELLED");
        update.setCancelTime(LocalDateTime.now());
        orderMapper.update(update);

        List<OrderItem> items = orderItemMapper.findByOrderId(order.getId());
        for (OrderItem item : items) {
            productMapper.increaseStock(item.getProductId(), item.getQuantity());
            String key = RedisKeyConstants.orderStockKey(item.getProductId());
            stringRedisTemplate.opsForValue().increment(key, item.getQuantity());
        }
        log.info("[Cancel] order cancelled orderNo={} items={}", orderNo, items.size());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void payOrder(String orderNo, Long userId) {
        Order order = orderMapper.findByOrderNo(orderNo)
                .orElseThrow(() -> new BusinessException(404, "订单不存在"));
        if (!"PENDING_PAYMENT".equals(order.getStatus())) {
            throw new BusinessException(400, "订单状态不合法，无法支付");
        }
        Order update = new Order();
        update.setId(order.getId());
        update.setStatus("PAID");
        orderMapper.update(update);
        log.info("[Pay] orderId={} userId={} → PAID", orderNo, userId);
    }

    @Override
    public OrderStatusVO getOrderStatus(String orderNo) {
        Order order = orderMapper.findByOrderNo(orderNo).orElse(null);
        OrderStatusVO vo = new OrderStatusVO();
        vo.setOrderId(orderNo);
        if (order == null) {
            // Consumer 尚未落库，返回处理中状态
            vo.setStatus("PROCESSING");
            vo.setRemainSeconds(1800);
            return vo;
        }
        vo.setStatus(order.getStatus());
        vo.setTotalPrice(order.getTotalPrice());
        long elapsed = order.getCreatedAt() != null
                ? ChronoUnit.SECONDS.between(order.getCreatedAt(), LocalDateTime.now()) : 0;
        vo.setRemainSeconds(Math.max(0, 1800 - elapsed));
        return vo;
    }
}
