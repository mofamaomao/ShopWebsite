package com.shop.service;

import com.shop.entity.Product;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;

public interface ProductService {
    PageVO<ProductVO> listProducts(int page, int size, String keyword);
    ProductVO getProduct(Long id);
    ProductVO createProduct(Product product);
    ProductVO updateProduct(Long id, Product product);
    void deleteProduct(Long id);
}
