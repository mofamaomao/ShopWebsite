package com.shop.controller;

import com.shop.common.Result;
import com.shop.service.UserOrderService;
import com.shop.vo.OrderDetailVO;
import com.shop.vo.OrderListItemVO;
import com.shop.vo.PageVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@Tag(name = "订单历史（需登录）")
@RestController
@RequestMapping("/api/user/orders")
@RequiredArgsConstructor
public class UserOrderController {

    private final UserOrderService userOrderService;

    @Operation(summary = "我的订单列表", description = "分页查询当前用户订单，status 不传则返回全部")
    @GetMapping
    public Result<PageVO<OrderListItemVO>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String status,
            Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        return Result.ok(userOrderService.getUserOrders(userId, page, size, status));
    }

    @Operation(summary = "订单详情", description = "返回订单 + 商品明细，非本人订单返回 403")
    @GetMapping("/{orderNo}")
    public Result<OrderDetailVO> detail(@PathVariable String orderNo,
                                        Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        return Result.ok(userOrderService.getUserOrderDetail(userId, orderNo));
    }

    @Operation(summary = "取消订单", description = "仅 PENDING_PAYMENT 状态可取消，恢复库存")
    @PostMapping("/{orderNo}/cancel")
    public Result<Void> cancel(@PathVariable String orderNo,
                               Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        userOrderService.cancelUserOrder(userId, orderNo);
        return Result.<Void>ok("订单已取消", null);
    }
}
