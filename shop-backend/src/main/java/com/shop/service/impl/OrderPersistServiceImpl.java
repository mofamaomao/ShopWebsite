package com.shop.service.impl;

import com.shop.config.RabbitMQConfig;
import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.entity.PointsRecord;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.PointsRecordMapper;
import com.shop.mapper.ProductMapper;
import com.shop.mapper.UserMapper;
import com.shop.mq.OrderCancelMessage;
import com.shop.mq.OrderMessage;
import com.shop.service.OrderPersistService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderPersistServiceImpl implements OrderPersistService {

    private final ProductMapper      productMapper;
    private final OrderMapper        orderMapper;
    private final OrderItemMapper    orderItemMapper;
    private final UserMapper         userMapper;
    private final PointsRecordMapper pointsRecordMapper;
    private final RabbitTemplate     rabbitTemplate;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void persist(OrderMessage message) {
        // 幂等检查：order_no 已存在则跳过
        if (orderMapper.existsByOrderNo(message.getOrderId())) {
            log.warn("[OrderPersist] duplicate orderId={}, skip", message.getOrderId());
            return;
        }

        BigDecimal total = BigDecimal.ZERO;
        List<OrderItem> items = new ArrayList<>();

        // 扣减 MySQL 库存
        for (OrderMessage.Item itemMsg : message.getItems()) {
            int updated = productMapper.decreaseStock(itemMsg.getProductId(), itemMsg.getQuantity());
            if (updated == 0) {
                throw new RuntimeException(
                        "[OrderPersist] MySQL 库存不足 productId=" + itemMsg.getProductId());
            }
            BigDecimal subtotal = itemMsg.getPrice().multiply(BigDecimal.valueOf(itemMsg.getQuantity()));
            OrderItem oi = new OrderItem();
            oi.setProductId(itemMsg.getProductId());
            oi.setQuantity(itemMsg.getQuantity());
            oi.setPrice(itemMsg.getPrice());
            oi.setProductName(itemMsg.getProductName() != null ? itemMsg.getProductName() : "");
            oi.setProductImg(itemMsg.getProductImg() != null ? itemMsg.getProductImg() : "");
            oi.setSubtotal(subtotal);
            items.add(oi);
            total = total.add(subtotal);
        }

        // 积分抵扣（与写库在同一事务，保证原子性）
        BigDecimal actualTotal = total;
        int usablePoints = message.getUsablePoints() != null ? message.getUsablePoints() : 0;
        BigDecimal pointsDeduction = message.getPointsDeduction() != null
                ? message.getPointsDeduction() : BigDecimal.ZERO;

        if (usablePoints > 0) {
            int deducted = userMapper.deductPoints(message.getUserId(), usablePoints);
            if (deducted == 0) {
                // 积分余额不足（并发场景），降级为全价
                log.warn("[OrderPersist] points insufficient, full price orderId={}", message.getOrderId());
                usablePoints = 0;
                pointsDeduction = BigDecimal.ZERO;
            } else {
                actualTotal = total.subtract(pointsDeduction);
                int newBalance = userMapper.getPoints(message.getUserId());
                PointsRecord pr = new PointsRecord();
                pr.setUserId(message.getUserId());
                pr.setType(2);
                pr.setPoints(-usablePoints);
                pr.setBalance(newBalance);
                pr.setSource("积分抵扣");
                pr.setOrderId(message.getOrderId());
                pr.setCreatedAt(LocalDateTime.now());
                pointsRecordMapper.insert(pr);
                log.info("[OrderPersist] points deducted={} orderId={}", usablePoints, message.getOrderId());
            }
        }

        // 写订单主表
        Order order = new Order();
        order.setOrderNo(message.getOrderId());
        order.setUserId(message.getUserId());
        order.setTotalPrice(actualTotal);
        order.setStatus("PENDING_PAYMENT");
        order.setReceiver(message.getReceiver());
        order.setPhone(message.getPhone());
        order.setFullAddress(message.getFullAddress());
        try {
            orderMapper.insert(order);
        } catch (DuplicateKeyException e) {
            log.warn("[OrderPersist] race-condition duplicate orderId={}, skip", message.getOrderId());
            return;
        }

        // 写订单明细
        for (OrderItem oi : items) {
            oi.setOrderId(order.getId());
            orderItemMapper.insert(oi);
        }

        log.info("[OrderPersist] order saved orderId={} total={}", message.getOrderId(), actualTotal);

        // 发送延迟取消消息
        OrderCancelMessage cancelMsg = OrderCancelMessage.builder()
                .orderId(message.getOrderId())
                .userId(message.getUserId())
                .orderCreateTime(message.getCreateTime())
                .build();
        rabbitTemplate.convertAndSend(RabbitMQConfig.ORDER_DELAY_EXCHANGE,
                RabbitMQConfig.ORDER_DELAY_KEY, cancelMsg);
        log.info("[OrderPersist] delay cancel message sent orderId={}", message.getOrderId());
    }

    @Override
    public boolean isProcessed(String orderId) {
        return orderMapper.existsByOrderNo(orderId);
    }
}
