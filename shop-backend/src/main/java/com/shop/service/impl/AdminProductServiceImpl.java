package com.shop.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.dto.AdminProductRequest;
import com.shop.entity.Brand;
import com.shop.entity.Category;
import com.shop.entity.Product;
import com.shop.mapper.BrandMapper;
import com.shop.mapper.CategoryMapper;
import com.shop.mapper.ProductMapper;
import com.shop.service.AdminProductService;
import com.shop.service.ProductSearchService;
import com.shop.vo.AdminProductVO;
import com.shop.vo.PageVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class AdminProductServiceImpl implements AdminProductService {

    private final ProductMapper productMapper;
    private final CategoryMapper categoryMapper;
    private final BrandMapper brandMapper;
    private final ProductSearchService productSearchService;

    @Override
    public PageVO<AdminProductVO> listProducts(int page, int size, Long categoryId, Long brandId,
                                               Integer status, String keyword) {
        PageHelper.startPage(page, size);
        List<Product> list = productMapper.findAdminProducts(categoryId, brandId, status, keyword);
        PageInfo<Product> info = new PageInfo<>(list);

        Map<Long, String> categoryNames = loadCategoryNames();
        Map<Long, String> brandNames = loadBrandNames();

        PageVO<AdminProductVO> vo = new PageVO<>();
        vo.setList(list.stream().map(p -> toVO(p, categoryNames, brandNames)).collect(Collectors.toList()));
        vo.setTotal(info.getTotal());
        vo.setPage(page);
        vo.setSize(size);
        return vo;
    }

    @Override
    @Transactional
    public AdminProductVO create(AdminProductRequest req) {
        Product product = new Product();
        product.setName(req.getName());
        product.setPrice(req.getPrice());
        product.setStock(req.getStock());
        product.setCategoryId(req.getCategoryId());
        product.setBrandId(req.getBrandId());
        product.setImageUrl(req.getImageUrl());
        product.setDescription(req.getDescription());
        product.setStatus(req.getStatus() != null ? req.getStatus() : 2);
        productMapper.insertAdmin(product);

        if (Integer.valueOf(1).equals(product.getStatus())) {
            productSearchService.syncSave(product);
        }
        return toVO(product, loadCategoryNames(), loadBrandNames());
    }

    @Override
    @Transactional
    public AdminProductVO update(Long id, AdminProductRequest req) {
        Product existing = productMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "商品不存在"));
        if (Integer.valueOf(1).equals(existing.getIsDeleted())) {
            throw new BusinessException(400, "商品已删除");
        }

        Product product = new Product();
        product.setId(id);
        product.setName(req.getName());
        product.setPrice(req.getPrice());
        product.setStock(req.getStock());
        product.setCategoryId(req.getCategoryId());
        product.setBrandId(req.getBrandId());
        product.setImageUrl(req.getImageUrl());
        product.setDescription(req.getDescription());
        product.setStatus(req.getStatus());
        productMapper.updateAdmin(product);

        Product updated = productMapper.findById(id).orElse(product);
        if (Integer.valueOf(1).equals(updated.getStatus())) {
            productSearchService.syncSave(updated);
        } else {
            productSearchService.syncDelete(id);
        }
        return toVO(updated, loadCategoryNames(), loadBrandNames());
    }

    @Override
    @Transactional
    public void delete(Long id) {
        productMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "商品不存在"));
        productMapper.softDelete(id);
        productSearchService.syncDelete(id);
    }

    @Override
    @Transactional
    public AdminProductVO toggleStatus(Long id, int status) {
        Product product = productMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "商品不存在"));
        if (Integer.valueOf(1).equals(product.getIsDeleted())) {
            throw new BusinessException(400, "商品已删除");
        }
        productMapper.updateStatus(id, status);
        product.setStatus(status);

        if (status == 1) {
            productSearchService.syncSave(product);
        } else {
            productSearchService.syncDelete(id);
        }
        return toVO(product, loadCategoryNames(), loadBrandNames());
    }

    private Map<Long, String> loadCategoryNames() {
        Map<Long, String> map = new HashMap<>();
        categoryMapper.findAll().forEach(c -> map.put(c.getId(), c.getName()));
        return map;
    }

    private Map<Long, String> loadBrandNames() {
        Map<Long, String> map = new HashMap<>();
        brandMapper.findAll().forEach(b -> map.put(b.getId(), b.getName()));
        return map;
    }

    private AdminProductVO toVO(Product p, Map<Long, String> catNames, Map<Long, String> brandNames) {
        AdminProductVO vo = new AdminProductVO();
        vo.setId(p.getId());
        vo.setName(p.getName());
        vo.setPrice(p.getPrice());
        vo.setStock(p.getStock());
        vo.setCategoryId(p.getCategoryId());
        vo.setCategoryName(p.getCategoryId() != null ? catNames.get(p.getCategoryId()) : null);
        vo.setBrandId(p.getBrandId());
        vo.setBrandName(p.getBrandId() != null ? brandNames.get(p.getBrandId()) : null);
        vo.setImageUrl(p.getImageUrl());
        vo.setDescription(p.getDescription());
        vo.setStatus(p.getStatus());
        vo.setIsDeleted(p.getIsDeleted());
        return vo;
    }
}
