package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.OrderCreateRequest;
import com.shop.service.OrderService;
import com.shop.vo.OrderStatusVO;
import com.shop.vo.OrderVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@Tag(name = "订单（需登录）")
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @Operation(summary = "创建订单", description = "Redis 预扣库存 + MQ 异步写 DB，立即返回 orderId + totalPrice")
    @PostMapping
    public Result<OrderVO> create(@Valid @RequestBody OrderCreateRequest request,
                                  Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        OrderVO vo = orderService.createOrder(userId, request);
        return Result.ok("订单处理中", vo);
    }

    @Operation(summary = "模拟支付", description = "仅 PENDING_PAYMENT 状态可支付，幂等")
    @PostMapping("/{orderId}/pay")
    public Result<Void> pay(@PathVariable String orderId, Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        orderService.payOrder(orderId, userId);
        return Result.<Void>ok("支付成功", null);
    }

    @Operation(summary = "查询订单状态", description = "返回 status + totalPrice + remainSeconds")
    @GetMapping("/{orderId}/status")
    public Result<OrderStatusVO> status(@PathVariable String orderId) {
        return Result.ok(orderService.getOrderStatus(orderId));
    }
}
