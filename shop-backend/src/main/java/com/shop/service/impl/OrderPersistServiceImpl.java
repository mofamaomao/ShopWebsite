package com.shop.service.impl;

import com.shop.config.RabbitMQConfig;
import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.ProductMapper;
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
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderPersistServiceImpl implements OrderPersistService {

    private final ProductMapper productMapper;
    private final OrderMapper orderMapper;
    private final OrderItemMapper orderItemMapper;
    private final RabbitTemplate rabbitTemplate;

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

        // 先扣减 MySQL 库存（失败则整体回滚）
        for (OrderMessage.Item itemMsg : message.getItems()) {
            int updated = productMapper.decreaseStock(itemMsg.getProductId(), itemMsg.getQuantity());
            if (updated == 0) {
                throw new RuntimeException(
                        "[OrderPersist] MySQL 库存不足 productId=" + itemMsg.getProductId());
            }
            OrderItem oi = new OrderItem();
            oi.setProductId(itemMsg.getProductId());
            oi.setQuantity(itemMsg.getQuantity());
            oi.setPrice(itemMsg.getPrice());
            items.add(oi);
            total = total.add(itemMsg.getPrice().multiply(BigDecimal.valueOf(itemMsg.getQuantity())));
        }

        // 写订单主表（order_no 唯一约束兜底幂等）
        Order order = new Order();
        order.setOrderNo(message.getOrderId());
        order.setUserId(message.getUserId());
        order.setTotalPrice(total);
        order.setStatus("PENDING_PAYMENT");
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

        log.info("[OrderPersist] order saved orderId={} total={}", message.getOrderId(), total);

        // 发送延迟取消消息（TTL 到期后路由到 order.cancel.queue）
        rabbitTemplate.convertAndSend("", RabbitMQConfig.ORDER_DELAY_QUEUE,
                new OrderCancelMessage(message.getOrderId()));
        log.info("[OrderPersist] delay cancel message sent orderId={}", message.getOrderId());
    }

    @Override
    public boolean isProcessed(String orderId) {
        return orderMapper.existsByOrderNo(orderId);
    }
}
