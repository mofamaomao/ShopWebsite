package com.shop.service;

import com.shop.entity.MqMessage;
import java.util.List;

public interface MqMessageService {
    void save(String orderId, String content);
    void markDelivered(String orderId);
    void markFailed(String orderId);
    void markDead(String orderId);
    List<MqMessage> findForRetry();
}
