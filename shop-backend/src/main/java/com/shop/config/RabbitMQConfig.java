package com.shop.config;

import com.shop.service.MqMessageService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.boot.autoconfigure.amqp.SimpleRabbitListenerContainerFactoryConfigurer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.amqp.rabbit.annotation.EnableRabbit;

@Slf4j
@Configuration
@EnableRabbit
public class RabbitMQConfig {

    public static final String ORDER_QUEUE    = "order.queue";
    public static final String ORDER_EXCHANGE = "order.exchange";
    public static final String ORDER_KEY      = "order.routing.key";
    public static final String ORDER_DLQ      = "order.dlq";
    public static final String ORDER_DLX      = "order.dlx";

    // ── 正常队列（绑定 DLX）────────────────────────────────────────────────
    @Bean
    public Queue orderQueue() {
        return QueueBuilder.durable(ORDER_QUEUE)
                .withArgument("x-dead-letter-exchange", ORDER_DLX)
                .withArgument("x-dead-letter-routing-key", ORDER_DLQ)
                .build();
    }

    @Bean
    public DirectExchange orderExchange() {
        return new DirectExchange(ORDER_EXCHANGE);
    }

    @Bean
    public Binding orderBinding() {
        return BindingBuilder.bind(orderQueue()).to(orderExchange()).with(ORDER_KEY);
    }

    // ── 死信队列 ─────────────────────────────────────────────────────────
    @Bean
    public DirectExchange dlxExchange() {
        return new DirectExchange(ORDER_DLX);
    }

    @Bean
    public Queue orderDlq() {
        return QueueBuilder.durable(ORDER_DLQ).build();
    }

    @Bean
    public Binding dlqBinding() {
        return BindingBuilder.bind(orderDlq()).to(dlxExchange()).with(ORDER_DLQ);
    }

    // ── JSON 消息序列化 ───────────────────────────────────────────────────
    @Bean
    public MessageConverter jsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory,
                                          MessageConverter jsonMessageConverter,
                                          MqMessageService mqMessageService) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(jsonMessageConverter);
        template.setMandatory(true);

        // Publisher Confirm 回调：ack→status=1，nack→status=2 触发定时重投
        template.setConfirmCallback((correlationData, ack, cause) -> {
            if (correlationData == null || correlationData.getId() == null) return;
            String orderId = correlationData.getId();
            if (ack) {
                mqMessageService.markDelivered(orderId);
            } else {
                log.error("[MQ] confirm nack orderId={} cause={}", orderId, cause);
                mqMessageService.markFailed(orderId);
            }
        });

        // Returns 回调：路由失败告警（exchange/routingKey 配置错误时触发）
        template.setReturnsCallback(returned ->
            log.error("[MQ] route failed exchange={} routingKey={} replyText={}",
                    returned.getExchange(), returned.getRoutingKey(), returned.getReplyText()));

        return template;
    }

    @Bean
    public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
            SimpleRabbitListenerContainerFactoryConfigurer configurer,
            ConnectionFactory connectionFactory,
            MessageConverter jsonMessageConverter) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        configurer.configure(factory, connectionFactory);
        factory.setMessageConverter(jsonMessageConverter);
        return factory;
    }
}
