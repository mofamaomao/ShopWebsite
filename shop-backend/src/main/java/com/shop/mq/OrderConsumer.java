package com.shop.mq;

import com.rabbitmq.client.Channel;
import com.shop.config.RabbitMQConfig;
import com.shop.service.OrderPersistService;
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
public class OrderConsumer {

    private final OrderPersistService orderPersistService;

    @RabbitListener(queues = RabbitMQConfig.ORDER_QUEUE)
    public void consume(OrderMessage message,
                        Channel channel,
                        @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag) throws IOException {
        log.info("[MQ] received orderId={} userId={}", message.getOrderId(), message.getUserId());
        try {
            orderPersistService.persist(message);
            channel.basicAck(deliveryTag, false);
        } catch (Exception e) {
            log.error("[MQ] consume failed orderId={}: {}", message.getOrderId(), e.getMessage());
            // requeue=false：重试超限后转入 DLQ
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
