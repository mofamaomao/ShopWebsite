package com.shop.mq;

import com.shop.config.RabbitMQConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

@Slf4j
@Component
@RequiredArgsConstructor
public class OrderProducer {

    private final RabbitTemplate rabbitTemplate;

    /**
     * 发送订单消息并等待 Broker confirm（最多 3s）。
     * @return true = ack；false = nack / 超时 / 异常（调用方应回滚 Redis 库存）
     */
    public boolean send(OrderMessage message) {
        CorrelationData cd = new CorrelationData(message.getOrderId());
        rabbitTemplate.convertAndSend(
                RabbitMQConfig.ORDER_EXCHANGE,
                RabbitMQConfig.ORDER_KEY,
                message,
                cd);
        try {
            CorrelationData.Confirm confirm = cd.getFuture().get(3, TimeUnit.SECONDS);
            if (confirm.isAck()) {
                log.info("[MQ] confirm ack orderId={}", message.getOrderId());
                return true;
            }
            log.error("[MQ] confirm nack orderId={} reason={}", message.getOrderId(), confirm.getReason());
            return false;
        } catch (TimeoutException e) {
            log.error("[MQ] confirm timeout orderId={}", message.getOrderId());
            return false;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        } catch (ExecutionException e) {
            log.error("[MQ] confirm exception orderId={}", message.getOrderId(), e.getCause().getMessage());
            return false;
        }
    }
}
