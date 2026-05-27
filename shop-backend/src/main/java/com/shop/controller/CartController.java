package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.CartAddRequest;
import com.shop.service.CartService;
import com.shop.vo.CartVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@Tag(name = "购物车（需登录）")
@RestController
@RequestMapping("/api/cart")
@RequiredArgsConstructor
public class CartController {

    private final CartService cartService;

    @Operation(summary = "加入购物车", description = "幂等操作，重复加购叠加数量；数据存 Redis Hash")
    @PostMapping
    public Result<Void> add(@Valid @RequestBody CartAddRequest request,
                            Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        cartService.addToCart(userId, request);
        return Result.ok();
    }

    @Operation(summary = "查看购物车", description = "从 Redis 读取后联查商品信息，计算合计")
    @GetMapping
    public Result<CartVO> get(Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        return Result.ok(cartService.getCart(userId));
    }
}
