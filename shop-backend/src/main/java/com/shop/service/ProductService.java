package com.shop.service;

import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;

public interface ProductService {
    PageVO<ProductVO> listProducts(int page, int size, String keyword);
    ProductVO getProduct(Long id);
}
