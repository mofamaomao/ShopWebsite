package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Data
public class OrderDetailVO {
    private Long id;
    private String orderNo;
    private BigDecimal totalPrice;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime payTime;
    private LocalDateTime cancelTime;
    private String remark;
    private List<OrderItemVO> items;
}
