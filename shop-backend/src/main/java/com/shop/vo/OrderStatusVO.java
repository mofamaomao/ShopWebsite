package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;

@Data
public class OrderStatusVO {
    private String orderId;
    private String status;
    private BigDecimal totalPrice;
    private long remainSeconds;
}
