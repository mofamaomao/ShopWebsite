package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class OrderVO {
    /** UUID 业务订单号，异步模式下立即返回，Consumer 落库后可查询状态 */
    private String orderId;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
}
