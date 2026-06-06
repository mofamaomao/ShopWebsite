package com.shop.service;

import com.shop.vo.OrderDetailVO;
import com.shop.vo.OrderListItemVO;
import com.shop.vo.PageVO;

public interface UserOrderService {

    PageVO<OrderListItemVO> getUserOrders(Long userId, int page, int size, String status);

    OrderDetailVO getUserOrderDetail(Long userId, String orderNo);

    void cancelUserOrder(Long userId, String orderNo);
}
