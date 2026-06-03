package com.shop.vo;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class BrandVO {
    private Long id;
    private String name;
    private String logoUrl;
    private String description;
    private LocalDateTime createdAt;
}
