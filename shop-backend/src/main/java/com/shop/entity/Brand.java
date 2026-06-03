package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class Brand {
    private Long id;
    private String name;
    private String logoUrl;
    private String description;
    private LocalDateTime createdAt;
}
