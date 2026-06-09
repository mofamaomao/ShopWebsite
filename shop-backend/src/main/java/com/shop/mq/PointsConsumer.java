package com.shop.mq;

import com.rabbitmq.client.Channel;
import com.shop.config.RabbitMQConfig;
import com.shop.mapper.PointsRecordMapper;
import com.shop.service.PointsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;

@Slf4j
@Component
@RequiredArgsConstructor
public class PointsConsumer {

    private final PointsService pointsService;
    private final PointsRecordMapper pointsRecordMapper;

    @Value("${points.earn-rate:10}")
    private int earnRate;

    @RabbitListener(queues = RabbitMQConfig.POINTS_QUEUE)
    public void onMessage(PointsMessage msg, Channel channel,
                          @Header(AmqpHeaders.DELIVERY_TAG) long tag) throws IOException {
        try {
            // 幂等检查：同一订单只发一次
            if (pointsRecordMapper.existsByOrderIdAndType(msg.getOrderId(), 1)) {
                log.info("[Points] already earned, skip orderId={}", msg.getOrderId());
                channel.basicAck(tag, false);
                return;
            }
            int points = msg.getPaidAmount()
                            .multiply(BigDecimal.valueOf(earnRate))
                            .setScale(0, RoundingMode.DOWN)
                            .intValue();
            if (points > 0) {
                pointsService.earnPoints(msg.getUserId(), points, msg.getOrderId());
            }
            channel.basicAck(tag, false);
        } catch (Exception e) {
            log.error("[Points] consume failed orderId={} err={}", msg.getOrderId(), e.getMessage(), e);
            channel.basicNack(tag, false, false); // 进死信队列
        }
    }
}
