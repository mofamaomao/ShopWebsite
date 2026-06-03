package com.shop.mq;

import com.shop.config.RabbitMQConfig;
import com.shop.service.MqMessageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderDlqConsumer {

    private final MqMessageService mqMessageService;

    @RabbitListener(queues = RabbitMQConfig.ORDER_DLQ)
    public void consumeDeadLetter(OrderMessage message) {
        log.error("[DLQ] 订单进入死信队列 orderId={} userId={}",
                message.getOrderId(), message.getUserId());
        // Demo 阶段记日志 + 更新 mq_message 状态为 DEAD，生产环境可接钉钉/邮件告警
        mqMessageService.markDead(message.getOrderId());
    }
}
