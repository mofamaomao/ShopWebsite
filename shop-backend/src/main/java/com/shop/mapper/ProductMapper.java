package com.shop.mapper;

import com.shop.entity.Product;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Optional;

@Mapper
public interface ProductMapper {

    Optional<Product> findById(Long id);

    Optional<Product> findByIdForUpdate(Long id);

    List<Product> findAll();

    List<Product> findByKeyword(@Param("keyword") String keyword);

    List<Product> findByCategory(String category);

    int insert(Product product);

    int update(Product product);

    int decreaseStock(@Param("id") Long id, @Param("quantity") int quantity);

    int deleteById(Long id);
}
