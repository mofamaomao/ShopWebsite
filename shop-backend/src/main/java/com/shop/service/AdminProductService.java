package com.shop.service;

import com.shop.dto.AdminProductRequest;
import com.shop.vo.AdminProductVO;
import com.shop.vo.PageVO;

public interface AdminProductService {
    PageVO<AdminProductVO> listProducts(int page, int size, Long categoryId, Long brandId,
                                        Integer status, String keyword);
    AdminProductVO create(AdminProductRequest req);
    AdminProductVO update(Long id, AdminProductRequest req);
    void delete(Long id);
    AdminProductVO toggleStatus(Long id, int status);
}
