package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class Category {
    private Long id;
    private String name;
    private Long parentId;
    private Integer sort;
    private String iconUrl;
    private LocalDateTime createdAt;
}
