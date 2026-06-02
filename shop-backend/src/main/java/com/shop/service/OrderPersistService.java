package com.shop.service;

import com.shop.mq.OrderMessage;

public interface OrderPersistService {
    /**
     * 幂等写入订单（order_no UNIQUE 保证）。
     * 在同一事务内完成：扣减 MySQL 库存 + 写 order + 写 order_item。
     */
    void persist(OrderMessage message);
}
