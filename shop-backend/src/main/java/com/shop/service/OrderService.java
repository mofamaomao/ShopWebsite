package com.shop.service;

import com.shop.dto.OrderCreateRequest;
import com.shop.vo.OrderVO;

public interface OrderService {
    OrderVO createOrder(Long userId, OrderCreateRequest request);
}
