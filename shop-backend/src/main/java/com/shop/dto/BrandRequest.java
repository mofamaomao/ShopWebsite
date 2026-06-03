package com.shop.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class BrandRequest {
    @NotBlank(message = "品牌名称不能为空")
    private String name;
    private String logoUrl;
    private String description;
}
