package com.shop.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.config.RabbitMQConfig;
import com.shop.dto.OrderCreateRequest;
import com.shop.entity.Address;
import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.entity.Product;
import com.shop.mapper.AddressMapper;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.ProductMapper;
import com.shop.mapper.UserMapper;
import com.shop.mq.OrderMessage;
import com.shop.mq.OrderProducer;
import com.shop.mq.PointsMessage;
import com.shop.service.CartService;
import com.shop.service.MqMessageService;
import com.shop.service.OrderService;
import com.shop.vo.OrderStatusVO;
import com.shop.vo.OrderVO;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
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
    private final AddressMapper       addressMapper;
    private final UserMapper          userMapper;
    private final StringRedisTemplate stringRedisTemplate;
    private final OrderProducer       orderProducer;
    private final RabbitTemplate      rabbitTemplate;
    private final MqMessageService    mqMessageService;
    private final CartService         cartService;
    private final ObjectMapper        objectMapper;

    @Value("${points.redeem-rate:100}")
    private int redeemRate;

    @Value("${points.max-redeem-pct:0.2}")
    private double maxRedeemPct;

    @Autowired
    @Qualifier("orderDeductScript")
    private DefaultRedisScript<Long> orderDeductScript;

    public OrderServiceImpl(ProductMapper productMapper,
                            OrderMapper orderMapper,
                            OrderItemMapper orderItemMapper,
                            AddressMapper addressMapper,
                            UserMapper userMapper,
                            StringRedisTemplate stringRedisTemplate,
                            OrderProducer orderProducer,
                            RabbitTemplate rabbitTemplate,
                            MqMessageService mqMessageService,
                            CartService cartService,
                            ObjectMapper objectMapper) {
        this.productMapper       = productMapper;
        this.orderMapper         = orderMapper;
        this.orderItemMapper     = orderItemMapper;
        this.addressMapper       = addressMapper;
        this.userMapper          = userMapper;
        this.stringRedisTemplate = stringRedisTemplate;
        this.orderProducer       = orderProducer;
        this.rabbitTemplate      = rabbitTemplate;
        this.mqMessageService    = mqMessageService;
        this.cartService         = cartService;
        this.objectMapper        = objectMapper;
    }

    /**
     * 异步下单：
     *   0. 地址校验快照
     *   1. 商品校验 + 价格快照
     *   2. Redis Lua 原子预扣库存
     *   2.5 积分抵扣计算（不执行扣减，传给 Consumer）
     *   3. 写 mq_message 表，失败回滚 Redis
     *   4. 发送 MQ
     *   5. 立即返回
     */
    @Override
    public OrderVO createOrder(Long userId, OrderCreateRequest req) {
        // Step 0: 校验并快照收货地址
        String receiver = null, phone = null, fullAddress = null;
        if (req.getAddressId() != null) {
            Address addr = addressMapper.findById(req.getAddressId())
                    .orElseThrow(() -> new BusinessException(400, "收货地址不存在"));
            if (!addr.getUserId().equals(userId)) {
                throw new BusinessException(403, "无权使用此地址");
            }
            receiver    = addr.getReceiver();
            phone       = addr.getPhone();
            fullAddress = addr.getProvince() + addr.getCity() + addr.getDistrict() + addr.getDetail();
        }

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
        BigDecimal totalPrice = items.stream()
                .map(i -> i.getPrice().multiply(BigDecimal.valueOf(i.getQuantity())))
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        // Step 2: Redis 预扣库存
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

        // Step 2.5: 积分抵扣预计算（实际扣减在 Consumer 事务内执行）
        int usablePoints = 0;
        BigDecimal pointsDeduction = BigDecimal.ZERO;
        if (Boolean.TRUE.equals(req.getUsePoints())) {
            int userPoints = userMapper.getPoints(userId);
            if (userPoints > 0) {
                BigDecimal maxDeductAmt = totalPrice.multiply(BigDecimal.valueOf(maxRedeemPct));
                int maxDeductPoints = maxDeductAmt.multiply(BigDecimal.valueOf(redeemRate))
                                                   .setScale(0, RoundingMode.DOWN).intValue();
                usablePoints = Math.min(userPoints, maxDeductPoints);
                if (usablePoints > 0) {
                    pointsDeduction = BigDecimal.valueOf(usablePoints)
                                                .divide(BigDecimal.valueOf(redeemRate), 2, RoundingMode.DOWN);
                }
            }
        }

        // Step 3: 写 mq_message 表
        String orderId = UUID.randomUUID().toString();
        OrderMessage message = new OrderMessage();
        message.setOrderId(orderId);
        message.setUserId(userId);
        message.setItems(items);
        message.setCreateTime(LocalDateTime.now());
        message.setReceiver(receiver);
        message.setPhone(phone);
        message.setFullAddress(fullAddress);
        message.setUsablePoints(usablePoints);
        message.setPointsDeduction(pointsDeduction);
        try {
            String content = objectMapper.writeValueAsString(message);
            mqMessageService.save(orderId, content);
        } catch (JsonProcessingException | RuntimeException e) {
            deducted.forEach(d -> rollbackRedisStock(d.getProductId(), d.getQuantity()));
            throw new BusinessException(500, "下单失败，请重试");
        }

        // Step 4: 异步发送 MQ
        orderProducer.send(message);
        cartService.clearCart(userId);

        // Step 5: 立即返回（展示折后价）
        BigDecimal displayPrice = totalPrice.subtract(pointsDeduction);
        OrderVO vo = new OrderVO();
        vo.setOrderId(orderId);
        vo.setTotalPrice(displayPrice);
        vo.setStatus("PENDING_PAYMENT");
        log.info("[Order] created orderId={} userId={} total={} pointsDeduction={}",
                orderId, userId, displayPrice, pointsDeduction);
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
        update.setPayTime(LocalDateTime.now());
        orderMapper.update(update);

        // 发放积分（异步，实付金额）
        try {
            PointsMessage pm = new PointsMessage(orderNo, order.getUserId(), order.getTotalPrice());
            rabbitTemplate.convertAndSend(RabbitMQConfig.POINTS_EXCHANGE, RabbitMQConfig.POINTS_KEY, pm);
        } catch (Exception e) {
            log.error("[Pay-mock] points message failed orderId={} err={}", orderNo, e.getMessage(), e);
        }
        log.info("[Pay] orderId={} userId={} → PAID", orderNo, userId);
    }

    @Override
    public OrderStatusVO getOrderStatus(String orderNo) {
        Order order = orderMapper.findByOrderNo(orderNo).orElse(null);
        OrderStatusVO vo = new OrderStatusVO();
        vo.setOrderId(orderNo);
        if (order == null) {
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
