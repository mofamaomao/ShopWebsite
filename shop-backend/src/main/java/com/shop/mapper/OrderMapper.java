package com.shop.mapper;

import com.shop.entity.Order;
import com.shop.vo.OrderListItemVO;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Optional;

@Mapper
public interface OrderMapper {

    Optional<Order> findById(Long id);

    Optional<Order> findByOrderNo(String orderNo);

    boolean existsByOrderNo(String orderNo);

    List<Order> findByUserId(Long userId);

    List<OrderListItemVO> findByUserIdWithFilter(@Param("userId") Long userId,
                                                  @Param("status") String status);

    List<Order> findAll();

    int insert(Order order);

    int update(Order order);

    int deleteById(Long id);
}
