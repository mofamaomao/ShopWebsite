package com.shop.mq;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderCancelMessage {
    private String orderId;
    private Long userId;
    private LocalDateTime orderCreateTime;
}
