package com.shop.service;

import com.shop.dto.BrandRequest;
import com.shop.vo.BrandVO;
import com.shop.vo.PageVO;

import java.util.List;

public interface AdminBrandService {
    List<BrandVO> listAll();
    PageVO<BrandVO> listPage(int page, int size, String keyword);
    BrandVO create(BrandRequest req);
    BrandVO update(Long id, BrandRequest req);
    void delete(Long id);
}
