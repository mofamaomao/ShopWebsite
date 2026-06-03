package com.shop.service;

import com.shop.mq.OrderMessage;

public interface OrderPersistService {
    void persist(OrderMessage message);
    boolean isProcessed(String orderId);
}
