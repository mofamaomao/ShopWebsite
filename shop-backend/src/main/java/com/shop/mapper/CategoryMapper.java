package com.shop.mapper;

import com.shop.entity.Category;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Optional;

@Mapper
public interface CategoryMapper {

    List<Category> findAll();

    Optional<Category> findById(Long id);

    int insert(Category category);

    int update(Category category);

    int deleteById(Long id);
}
