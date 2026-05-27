package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class OrderVO {
    private Long orderId;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
}
