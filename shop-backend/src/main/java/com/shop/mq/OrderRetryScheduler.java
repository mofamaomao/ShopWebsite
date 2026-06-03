package com.shop.mq;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.shop.entity.MqMessage;
import com.shop.service.MqMessageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderRetryScheduler {

    private final MqMessageService mqMessageService;
    private final OrderProducer    orderProducer;
    private final ObjectMapper     objectMapper;

    /** 每 60s 扫描 status=2 且 retry_count < 3 的记录，重新投递 */
    @Scheduled(fixedDelay = 60_000)
    public void retryFailedMessages() {
        List<MqMessage> list = mqMessageService.findForRetry();
        if (list.isEmpty()) return;
        log.info("[Retry] found {} message(s) to retry", list.size());
        for (MqMessage msg : list) {
            try {
                OrderMessage orderMessage = objectMapper.readValue(msg.getContent(), OrderMessage.class);
                orderProducer.send(orderMessage);
                log.info("[Retry] resent orderId={} retryCount={}", msg.getId(), msg.getRetryCount());
                // confirm 回调异步更新 status=1（ack）或 retry_count++（nack）
            } catch (Exception e) {
                log.error("[Retry] resend error orderId={}", msg.getId(), e);
            }
        }
    }
}
