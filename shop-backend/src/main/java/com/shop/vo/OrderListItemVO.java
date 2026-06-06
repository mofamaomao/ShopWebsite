package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class OrderListItemVO {
    private Long id;
    private String orderNo;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime payTime;
    private int itemCount;
}
