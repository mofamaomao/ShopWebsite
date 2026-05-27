package com.shop.mapper;

import com.shop.entity.Product;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Optional;

@Mapper
public interface ProductMapper {

    Optional<Product> findById(Long id);

    List<Product> findAll();

    List<Product> findByCategory(String category);

    int insert(Product product);

    int update(Product product);

    int deleteById(Long id);
}
