package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.OrderCreateRequest;
import com.shop.service.OrderService;
import com.shop.vo.OrderVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "订单（需登录）")
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @Operation(summary = "创建订单", description = "SELECT FOR UPDATE 锁行校验库存，原子扣减后写入订单")
    @PostMapping
    public Result<OrderVO> create(@Valid @RequestBody OrderCreateRequest request,
                                  Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        return Result.ok(orderService.createOrder(userId, request));
    }
}
