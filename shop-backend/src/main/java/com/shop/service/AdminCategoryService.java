package com.shop.service;

import com.shop.dto.CategoryRequest;
import com.shop.vo.CategoryVO;

import java.util.List;

public interface AdminCategoryService {
    List<CategoryVO> getTree();
    CategoryVO create(CategoryRequest req);
    CategoryVO update(Long id, CategoryRequest req);
    void delete(Long id);
}
