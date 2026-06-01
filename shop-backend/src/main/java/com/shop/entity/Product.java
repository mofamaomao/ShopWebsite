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
    // 秒杀扩展字段
    private Integer isSeckill;
    private Integer seckillStock;
    private BigDecimal seckillPrice;
}
