package com.shop.service.impl;

import com.shop.entity.MqMessage;
import com.shop.mapper.MqMessageMapper;
import com.shop.service.MqMessageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class MqMessageServiceImpl implements MqMessageService {

    private final MqMessageMapper mqMessageMapper;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void save(String orderId, String content) {
        MqMessage msg = new MqMessage();
        msg.setId(orderId);
        msg.setContent(content);
        msg.setStatus(MqMessage.STATUS_PENDING);
        msg.setRetryCount(0);
        mqMessageMapper.insert(msg);
    }

    @Override
    public void markDelivered(String orderId) {
        mqMessageMapper.updateStatus(orderId, MqMessage.STATUS_DELIVERED);
        log.info("[MqMessage] delivered orderId={}", orderId);
    }

    @Override
    public void markFailed(String orderId) {
        mqMessageMapper.markFailed(orderId);
        log.warn("[MqMessage] failed orderId={}", orderId);
    }

    @Override
    public void markDead(String orderId) {
        mqMessageMapper.markDead(orderId);
        log.error("[MqMessage] dead orderId={}", orderId);
    }

    @Override
    public List<MqMessage> findForRetry() {
        return mqMessageMapper.findForRetry();
    }
}
