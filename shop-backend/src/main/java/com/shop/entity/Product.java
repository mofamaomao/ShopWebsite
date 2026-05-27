package com.shop.entity;

import lombok.Data;
import java.math.BigDecimal;

@Data
public class Product {

    private Long id;
    private String name;
    private BigDecimal price;
    private Integer stock;
    private String category;
    private String imageUrl;
    private String description;
}
