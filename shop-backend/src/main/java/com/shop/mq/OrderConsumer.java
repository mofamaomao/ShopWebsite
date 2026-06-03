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
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderConsumer {

    private final OrderPersistService orderPersistService;
    // 消费端重试计数（单实例 Demo，分布式场景改用 Redis 计数）
    private final ConcurrentHashMap<String, AtomicInteger> retryMap = new ConcurrentHashMap<>();

    @RabbitListener(queues = RabbitMQConfig.ORDER_QUEUE)
    public void consume(OrderMessage message,
                        Channel channel,
                        @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag) throws IOException {
        String orderId = message.getOrderId();
        log.info("[Consumer] received orderId={} userId={}", orderId, message.getUserId());

        // 幂等快路径：已处理则直接 ACK，不进事务
        if (orderPersistService.isProcessed(orderId)) {
            log.info("[Consumer] duplicate orderId={}, skip", orderId);
            channel.basicAck(deliveryTag, false);
            retryMap.remove(orderId);
            return;
        }

        try {
            orderPersistService.persist(message);
            channel.basicAck(deliveryTag, false);
            retryMap.remove(orderId);
            log.info("[Consumer] processed orderId={}", orderId);
        } catch (Exception e) {
            int retries = retryMap.computeIfAbsent(orderId, k -> new AtomicInteger(0))
                                  .incrementAndGet();
            log.error("[Consumer] failed orderId={} retries={}", orderId, retries, e);
            // 重试 < 3 次：requeue=true 重新投递；否则 requeue=false 进 DLQ
            boolean requeue = retries < 3;
            channel.basicNack(deliveryTag, false, requeue);
            if (!requeue) retryMap.remove(orderId);
        }
    }
}
