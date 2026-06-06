package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;

@Data
public class OrderItemVO {
    private Long productId;
    private String productName;
    private String productImg;
    private Integer quantity;
    private BigDecimal price;
    private BigDecimal subtotal;
}
