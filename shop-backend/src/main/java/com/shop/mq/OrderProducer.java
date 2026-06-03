package com.shop.mq;

import com.shop.config.RabbitMQConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderProducer {

    private final RabbitTemplate rabbitTemplate;

    /**
     * 异步发送订单消息。confirm 结果由 RabbitMQConfig.confirmCallback 处理，
     * 异步更新 mq_message 表 status（1=delivered / 2=failed）。
     */
    public void send(OrderMessage message) {
        CorrelationData cd = new CorrelationData(message.getOrderId());
        rabbitTemplate.convertAndSend(RabbitMQConfig.ORDER_EXCHANGE,
                                      RabbitMQConfig.ORDER_KEY, message, cd);
        log.info("[MQ] sent orderId={}", message.getOrderId());
    }
}
