package com.shop.service;

import com.shop.entity.Product;
import com.shop.vo.SearchResultVO;

import java.math.BigDecimal;
import java.util.List;

public interface ProductSearchService {

    /** Bulk sync all products from MySQL to ES. Returns count synced. */
    int bulkInit(List<Product> products);

    /** Upsert a single product document. On failure: logs + writes sync_fail_log. */
    void syncSave(Product product);

    /** Delete a product document. On failure: logs + writes sync_fail_log. */
    void syncDelete(Long productId);

    /**
     * Full-text search via ES with optional category/price/sort filters.
     * Returns highlight-enriched products + category aggregation buckets.
     */
    SearchResultVO search(String keyword, String category,
                          BigDecimal minPrice, BigDecimal maxPrice,
                          String sort, int page, int size);
}
