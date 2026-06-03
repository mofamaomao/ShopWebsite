package com.shop.mq;

import com.rabbitmq.client.Channel;
import com.shop.config.RabbitMQConfig;
import com.shop.service.OrderService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderCancelConsumer {

    private final OrderService orderService;

    @RabbitListener(queues = RabbitMQConfig.ORDER_CANCEL_QUEUE)
    public void consumeCancel(OrderCancelMessage message,
                              Channel channel,
                              @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag) throws IOException {
        String orderId = message.getOrderId();
        log.info("[CancelConsumer] received orderId={}", orderId);
        try {
            orderService.cancelOrder(orderId);
            channel.basicAck(deliveryTag, false);
        } catch (Exception e) {
            log.error("[CancelConsumer] failed orderId={}", orderId, e);
            // requeue=false：不重试，避免无限循环
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
