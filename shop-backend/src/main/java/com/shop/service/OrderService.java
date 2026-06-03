package com.shop.service;

import com.shop.dto.OrderCreateRequest;
import com.shop.vo.OrderStatusVO;
import com.shop.vo.OrderVO;

public interface OrderService {
    OrderVO createOrder(Long userId, OrderCreateRequest request);

    void cancelOrder(String orderNo);

    void payOrder(String orderNo, Long userId);

    OrderStatusVO getOrderStatus(String orderNo);
}
