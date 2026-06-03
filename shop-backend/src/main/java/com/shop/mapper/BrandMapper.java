package com.shop.mapper;

import com.shop.entity.Brand;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Optional;

@Mapper
public interface BrandMapper {

    List<Brand> findAll();

    List<Brand> findByKeyword(@Param("keyword") String keyword);

    Optional<Brand> findById(Long id);

    int insert(Brand brand);

    int update(Brand brand);

    int deleteById(Long id);
}
