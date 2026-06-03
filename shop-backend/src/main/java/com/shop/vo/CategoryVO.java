package com.shop.vo;

import lombok.Data;
import java.time.LocalDateTime;
import java.util.List;

@Data
public class CategoryVO {
    private Long id;
    private String name;
    private Long parentId;
    private Integer sort;
    private String iconUrl;
    private LocalDateTime createdAt;
    private List<CategoryVO> children;
}
