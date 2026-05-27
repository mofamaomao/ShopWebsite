package com.shop.mapper;

import com.shop.entity.Order;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Optional;

@Mapper
public interface OrderMapper {

    Optional<Order> findById(Long id);

    List<Order> findByUserId(Long userId);

    List<Order> findAll();

    int insert(Order order);

    int update(Order order);

    int deleteById(Long id);
}
