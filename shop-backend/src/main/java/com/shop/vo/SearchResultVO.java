package com.shop.vo;

import lombok.Data;
import java.util.List;

@Data
public class SearchResultVO {
    private List<ProductVO> products;
    private long total;
    private List<CategoryBucketVO> categoryBuckets;
}
