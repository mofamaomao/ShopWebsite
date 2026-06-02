package com.shop.service;

import com.shop.entity.Product;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;

import java.util.List;

public interface ProductSearchService {

    /** Bulk sync all products from MySQL to ES. Returns count synced. */
    int bulkInit(List<Product> products);

    /** Upsert a single product document. On failure: logs + writes sync_fail_log. */
    void syncSave(Product product);

    /** Delete a product document. On failure: logs + writes sync_fail_log. */
    void syncDelete(Long productId);

    /**
     * Full-text search via ES multi_match on name/description.
     * Returns highlight-enriched ProductVO list.
     */
    PageVO<ProductVO> search(String keyword, int page, int size);
}
