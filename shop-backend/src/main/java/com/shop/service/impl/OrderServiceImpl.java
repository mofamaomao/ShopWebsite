package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
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
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {

    private final ProductMapper productMapper;
    private final OrderMapper orderMapper;
    private final OrderItemMapper orderItemMapper;

    @Override
    @Transactional
    public OrderVO createOrder(Long userId, OrderCreateRequest req) {
        BigDecimal total = BigDecimal.ZERO;
        List<OrderItem> itemsToInsert = new ArrayList<>();

        for (OrderCreateRequest.OrderItemRequest itemReq : req.getItems()) {
            // SELECT FOR UPDATE 锁行，防止超卖
            Product product = productMapper.findByIdForUpdate(itemReq.getProductId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));

            if (product.getStock() < itemReq.getQuantity()) {
                throw new BusinessException(ErrorCode.STOCK_INSUFFICIENT);
            }

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
    }
}
