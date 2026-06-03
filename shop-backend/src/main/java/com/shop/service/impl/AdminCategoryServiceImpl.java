package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.dto.CategoryRequest;
import com.shop.entity.Category;
import com.shop.mapper.CategoryMapper;
import com.shop.service.AdminCategoryService;
import com.shop.vo.CategoryVO;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AdminCategoryServiceImpl implements AdminCategoryService {

    private final CategoryMapper categoryMapper;

    @Override
    public List<CategoryVO> getTree() {
        List<Category> all = categoryMapper.findAll();
        List<CategoryVO> voList = all.stream().map(this::toVO).collect(Collectors.toList());

        Map<Long, List<CategoryVO>> byParent = voList.stream()
                .filter(v -> v.getParentId() != null)
                .collect(Collectors.groupingBy(CategoryVO::getParentId));

        List<CategoryVO> roots = voList.stream()
                .filter(v -> v.getParentId() == null)
                .collect(Collectors.toList());

        roots.forEach(r -> r.setChildren(byParent.getOrDefault(r.getId(), new ArrayList<>())));
        return roots;
    }

    @Override
    public CategoryVO create(CategoryRequest req) {
        Category cat = new Category();
        cat.setName(req.getName());
        cat.setParentId(req.getParentId());
        cat.setSort(req.getSort() != null ? req.getSort() : 0);
        cat.setIconUrl(req.getIconUrl());
        categoryMapper.insert(cat);
        return toVO(cat);
    }

    @Override
    public CategoryVO update(Long id, CategoryRequest req) {
        categoryMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "分类不存在"));
        Category cat = new Category();
        cat.setId(id);
        cat.setName(req.getName());
        cat.setParentId(req.getParentId());
        cat.setSort(req.getSort());
        cat.setIconUrl(req.getIconUrl());
        categoryMapper.update(cat);
        return toVO(categoryMapper.findById(id).orElse(cat));
    }

    @Override
    public void delete(Long id) {
        categoryMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "分类不存在"));
        categoryMapper.deleteById(id);
    }

    private CategoryVO toVO(Category c) {
        CategoryVO vo = new CategoryVO();
        vo.setId(c.getId());
        vo.setName(c.getName());
        vo.setParentId(c.getParentId());
        vo.setSort(c.getSort());
        vo.setIconUrl(c.getIconUrl());
        vo.setCreatedAt(c.getCreatedAt());
        return vo;
    }
}
