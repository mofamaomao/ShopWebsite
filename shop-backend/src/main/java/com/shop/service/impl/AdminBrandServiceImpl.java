package com.shop.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.dto.BrandRequest;
import com.shop.entity.Brand;
import com.shop.mapper.BrandMapper;
import com.shop.service.AdminBrandService;
import com.shop.vo.BrandVO;
import com.shop.vo.PageVO;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AdminBrandServiceImpl implements AdminBrandService {

    private final BrandMapper brandMapper;

    @Override
    public List<BrandVO> listAll() {
        return brandMapper.findAll().stream().map(this::toVO).collect(Collectors.toList());
    }

    @Override
    public PageVO<BrandVO> listPage(int page, int size, String keyword) {
        PageHelper.startPage(page, size);
        List<Brand> list = brandMapper.findByKeyword(keyword);
        PageInfo<Brand> info = new PageInfo<>(list);

        PageVO<BrandVO> vo = new PageVO<>();
        vo.setList(list.stream().map(this::toVO).collect(Collectors.toList()));
        vo.setTotal(info.getTotal());
        vo.setPage(page);
        vo.setSize(size);
        return vo;
    }

    @Override
    public BrandVO create(BrandRequest req) {
        Brand brand = new Brand();
        brand.setName(req.getName());
        brand.setLogoUrl(req.getLogoUrl());
        brand.setDescription(req.getDescription());
        brandMapper.insert(brand);
        return toVO(brand);
    }

    @Override
    public BrandVO update(Long id, BrandRequest req) {
        brandMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "品牌不存在"));
        Brand brand = new Brand();
        brand.setId(id);
        brand.setName(req.getName());
        brand.setLogoUrl(req.getLogoUrl());
        brand.setDescription(req.getDescription());
        brandMapper.update(brand);
        return toVO(brandMapper.findById(id).orElse(brand));
    }

    @Override
    public void delete(Long id) {
        brandMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "品牌不存在"));
        brandMapper.deleteById(id);
    }

    private BrandVO toVO(Brand b) {
        BrandVO vo = new BrandVO();
        vo.setId(b.getId());
        vo.setName(b.getName());
        vo.setLogoUrl(b.getLogoUrl());
        vo.setDescription(b.getDescription());
        vo.setCreatedAt(b.getCreatedAt());
        return vo;
    }
}
