package com.shop.service.impl;

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
import com.shop.service.OrderService;
import com.shop.vo.OrderVO;
import lombok.RequiredArgsConstructor;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {

    private final ProductMapper productMapper;
    private final OrderMapper orderMapper;
    private final OrderItemMapper orderItemMapper;
    private final RedissonClient redissonClient;

    @Override
    @Transactional
    public OrderVO createOrder(Long userId, OrderCreateRequest req) {
        // 选择 userId 粒度而非 productId 粒度的原因：
        // 同一用户并发下单概率更高，productId 粒度会造成热点商品锁争抢；
        // DB 的 UPDATE WHERE stock>=qty 作为最后一道安全网，防止锁失效时超卖。
        String lockKey = RedisKeyConstants.ORDER_LOCK + userId;
        RLock lock = redissonClient.getLock(lockKey);
        boolean acquired;
        try {
            acquired = lock.tryLock(3, 10, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.SYSTEM_BUSY);
        }
        if (!acquired) {
            throw new BusinessException(ErrorCode.SYSTEM_BUSY);
        }

        try {
            BigDecimal total = BigDecimal.ZERO;
            List<OrderItem> itemsToInsert = new ArrayList<>();

            for (OrderCreateRequest.OrderItemRequest itemReq : req.getItems()) {
                Product product = productMapper.findById(itemReq.getProductId())
                        .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));

                if (product.getStock() < itemReq.getQuantity()) {
                    throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
                }

                // AND stock >= qty 乐观检查，双重保险
                int updated = productMapper.decreaseStock(product.getId(), itemReq.getQuantity());
                if (updated == 0) {
                    throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
                }

                BigDecimal subtotal = product.getPrice().multiply(BigDecimal.valueOf(itemReq.getQuantity()));
                total = total.add(subtotal);

                OrderItem item = new OrderItem();
                item.setProductId(product.getId());
                item.setQuantity(itemReq.getQuantity());
                item.setPrice(product.getPrice());
                itemsToInsert.add(item);
            }

            Order order = new Order();
            order.setUserId(userId);
            order.setTotalPrice(total);
            order.setStatus("PENDING");
            orderMapper.insert(order);

            itemsToInsert.forEach(item -> {
                item.setOrderId(order.getId());
                orderItemMapper.insert(item);
            });

            OrderVO vo = new OrderVO();
            vo.setOrderId(order.getId());
            vo.setTotalPrice(total);
            vo.setStatus("PENDING");
            vo.setCreatedAt(order.getCreatedAt());
            return vo;
        } finally {
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        }
    }
}
