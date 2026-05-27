package com.shop.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Order {

    private Long id;
    private Long userId;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
}
