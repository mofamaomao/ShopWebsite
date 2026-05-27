package com.shop.mapper;

import com.shop.entity.OrderItem;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;

@Mapper
public interface OrderItemMapper {

    int insert(OrderItem orderItem);

    List<OrderItem> findByOrderId(Long orderId);
}
