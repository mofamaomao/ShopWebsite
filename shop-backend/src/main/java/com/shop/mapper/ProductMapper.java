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

    int increaseStock(@Param("id") Long id, @Param("quantity") int quantity);

    int deleteById(Long id);

    /** 查询秒杀库存（is_seckill=1 才返回，否则 null） */
    Integer findSeckillStockById(Long id);

    List<Product> findAdminProducts(@Param("categoryId") Long categoryId,
                                    @Param("brandId") Long brandId,
                                    @Param("status") Integer status,
                                    @Param("keyword") String keyword);

    int updateStatus(@Param("id") Long id, @Param("status") int status);

    int softDelete(Long id);

    int insertAdmin(Product product);

    int updateAdmin(Product product);
}
