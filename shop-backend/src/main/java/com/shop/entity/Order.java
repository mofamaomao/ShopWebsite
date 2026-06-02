package com.shop.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Order {

    private Long id;
    /** 业务订单号（UUID），Producer 预生成，Consumer 写库，用于幂等校验 */
    private String orderNo;
    private Long userId;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
}
