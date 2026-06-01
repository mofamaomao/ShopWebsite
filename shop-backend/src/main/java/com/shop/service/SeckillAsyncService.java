package com.shop.service;

import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.entity.Product;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.ProductMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

@Slf4j
@Service
@RequiredArgsConstructor
public class SeckillAsyncService {

    private final ProductMapper    productMapper;
    private final OrderMapper      orderMapper;
    private final OrderItemMapper  orderItemMapper;

    @Async("seckillExecutor")
    @Transactional
    public void writeOrderAsync(Long userId, Long productId) {
        try {
            Product product = productMapper.findById(productId)
                    .orElseThrow(() -> new RuntimeException("商品不存在: " + productId));

            BigDecimal price = (product.getSeckillPrice() != null)
                    ? product.getSeckillPrice()
                    : product.getPrice();

            Order order = new Order();
            order.setUserId(userId);
            order.setTotalPrice(price);
            order.setStatus("PENDING");
            orderMapper.insert(order);

            OrderItem item = new OrderItem();
            item.setOrderId(order.getId());
            item.setProductId(productId);
            item.setQuantity(1);
            item.setPrice(price);
            orderItemMapper.insert(item);

            log.info("秒杀订单落库成功 userId={} productId={} orderId={}", userId, productId, order.getId());
        } catch (Exception e) {
            log.error("秒杀订单落库失败 userId={} productId={}", userId, productId, e);
            throw new RuntimeException("秒杀订单落库失败", e);
        }
    }
}
