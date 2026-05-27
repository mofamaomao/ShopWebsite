package com.shop.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.service.ProductService;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ProductServiceImpl implements ProductService {

    private final ProductMapper productMapper;

    @Override
    public PageVO<ProductVO> listProducts(int page, int size, String keyword) {
        PageHelper.startPage(page, size);
        List<Product> list = productMapper.findByKeyword(keyword);
        PageInfo<Product> pageInfo = new PageInfo<>(list);

        PageVO<ProductVO> pageVO = new PageVO<>();
        pageVO.setList(list.stream().map(this::toVO).collect(Collectors.toList()));
        pageVO.setTotal(pageInfo.getTotal());
        pageVO.setPage(page);
        pageVO.setSize(size);
        return pageVO;
    }

    @Override
    public ProductVO getProduct(Long id) {
        return productMapper.findById(id)
                .map(this::toVO)
                .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
    }

    private ProductVO toVO(Product p) {
        ProductVO vo = new ProductVO();
        vo.setId(p.getId());
        vo.setName(p.getName());
        vo.setPrice(p.getPrice());
        vo.setStock(p.getStock());
        vo.setCategory(p.getCategory());
        vo.setImageUrl(p.getImageUrl());
        vo.setDescription(p.getDescription());
        return vo;
    }
}
