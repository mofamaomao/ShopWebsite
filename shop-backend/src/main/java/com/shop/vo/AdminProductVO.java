package com.shop.vo;

import lombok.Data;
import java.math.BigDecimal;

@Data
public class AdminProductVO {
    private Long id;
    private String name;
    private BigDecimal price;
    private Integer stock;
    private Long categoryId;
    private String categoryName;
    private Long brandId;
    private String brandName;
    private String imageUrl;
    private String description;
    private Integer status;
    private Integer isDeleted;
}
