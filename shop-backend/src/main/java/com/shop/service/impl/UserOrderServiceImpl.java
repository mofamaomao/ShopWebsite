package com.shop.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.common.RedisKeyConstants;
import com.shop.entity.Order;
import com.shop.entity.OrderItem;
import com.shop.mapper.OrderItemMapper;
import com.shop.mapper.OrderMapper;
import com.shop.mapper.ProductMapper;
import com.shop.service.UserOrderService;
import com.shop.vo.OrderDetailVO;
import com.shop.vo.OrderItemVO;
import com.shop.vo.OrderListItemVO;
import com.shop.vo.PageVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class UserOrderServiceImpl implements UserOrderService {

    private final OrderMapper orderMapper;
    private final OrderItemMapper orderItemMapper;
    private final ProductMapper productMapper;
    private final StringRedisTemplate stringRedisTemplate;

    @Override
    public PageVO<OrderListItemVO> getUserOrders(Long userId, int page, int size, String status) {
        PageHelper.startPage(page, size);
        List<OrderListItemVO> list = orderMapper.findByUserIdWithFilter(userId, status);
        PageInfo<OrderListItemVO> info = new PageInfo<>(list);

        PageVO<OrderListItemVO> vo = new PageVO<>();
        vo.setList(info.getList());
        vo.setTotal(info.getTotal());
        vo.setPage(page);
        vo.setSize(size);
        return vo;
    }

    @Override
    public OrderDetailVO getUserOrderDetail(Long userId, String orderNo) {
        Order order = orderMapper.findByOrderNo(orderNo)
                .orElseThrow(() -> new BusinessException(404, "订单不存在"));
        if (!order.getUserId().equals(userId)) {
            throw new BusinessException(403, "无权查看此订单");
        }

        List<OrderItem> items = orderItemMapper.findByOrderId(order.getId());

        OrderDetailVO vo = new OrderDetailVO();
        vo.setId(order.getId());
        vo.setOrderNo(order.getOrderNo());
        vo.setTotalPrice(order.getTotalPrice());
        vo.setStatus(order.getStatus());
        vo.setCreatedAt(order.getCreatedAt());
        vo.setPayTime(order.getPayTime());
        vo.setCancelTime(order.getCancelTime());
        vo.setRemark(order.getRemark());
        vo.setReceiver(order.getReceiver());
        vo.setPhone(order.getPhone());
        vo.setFullAddress(order.getFullAddress());
        vo.setItems(items.stream().map(this::toItemVO).collect(Collectors.toList()));
        return vo;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void cancelUserOrder(Long userId, String orderNo) {
        Order order = orderMapper.findByOrderNo(orderNo)
                .orElseThrow(() -> new BusinessException(404, "订单不存在"));
        if (!order.getUserId().equals(userId)) {
            throw new BusinessException(403, "无权操作此订单");
        }
        if (!"PENDING_PAYMENT".equals(order.getStatus())) {
            throw new BusinessException(400, "只有待支付订单可以取消");
        }

        Order update = new Order();
        update.setId(order.getId());
        update.setStatus("CANCELLED");
        update.setCancelTime(LocalDateTime.now());
        orderMapper.update(update);

        List<OrderItem> items = orderItemMapper.findByOrderId(order.getId());
        for (OrderItem item : items) {
            productMapper.increaseStock(item.getProductId(), item.getQuantity());
            String key = RedisKeyConstants.orderStockKey(item.getProductId());
            stringRedisTemplate.opsForValue().increment(key, item.getQuantity());
        }
        log.info("[UserCancel] 订单已取消 orderNo={} userId={} items={}", orderNo, userId, items.size());
    }

    private OrderItemVO toItemVO(OrderItem item) {
        OrderItemVO vo = new OrderItemVO();
        vo.setProductId(item.getProductId());
        vo.setProductName(item.getProductName());
        vo.setProductImg(item.getProductImg());
        vo.setQuantity(item.getQuantity());
        vo.setPrice(item.getPrice());
        vo.setSubtotal(item.getSubtotal());
        return vo;
    }
}
