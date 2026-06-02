package com.shop.service;

import com.shop.entity.Product;
import com.shop.vo.ProductVO;
import com.shop.vo.SearchResultVO;

import java.math.BigDecimal;

public interface ProductService {
    /**
     * @param source pass "mysql" to force MySQL path (performance testing); otherwise routes
     *               by whether any ES-specific params are present
     */
    SearchResultVO listProducts(int page, int size, String keyword,
                                String category, BigDecimal minPrice, BigDecimal maxPrice,
                                String sort, String source);

    ProductVO getProduct(Long id);
    ProductVO createProduct(Product product);
    ProductVO updateProduct(Long id, Product product);
    void deleteProduct(Long id);
}
