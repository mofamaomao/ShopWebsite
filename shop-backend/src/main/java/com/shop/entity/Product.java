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
    // 管理后台扩展字段
    private Long brandId;
    private Long categoryId;
    private Integer status;      // 0下架 1上架 2草稿
    private Integer isDeleted;   // 0正常 1软删除
}
