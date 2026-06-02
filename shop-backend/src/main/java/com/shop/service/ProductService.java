package com.shop.service;

import com.shop.entity.Product;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;

public interface ProductService {
    /**
     * @param source pass "mysql" to force MySQL path (performance testing); otherwise auto-routes
     *               keyword→ES, no keyword→MySQL
     */
    PageVO<ProductVO> listProducts(int page, int size, String keyword, String source);
    ProductVO getProduct(Long id);
    ProductVO createProduct(Product product);
    ProductVO updateProduct(Long id, Product product);
    void deleteProduct(Long id);
}
