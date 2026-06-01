package com.shop.controller;

import com.shop.common.Result;
import com.shop.service.SeckillService;
import com.shop.vo.SeckillVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "秒杀")
@RestController
@RequiredArgsConstructor
public class SeckillController {

    private final SeckillService seckillService;

    @Operation(summary = "秒杀库存预热（Admin）",
               description = "将 seckill_stock 写入 Redis Hash，TTL 1h。无需鉴权，Demo 用。")
    @PostMapping("/api/admin/seckill/init")
    public Result<Void> initStock(@RequestParam Long productId) {
        seckillService.initSeckill(productId);
        return Result.ok();
    }

    @Operation(summary = "秒杀下单",
               description = "令牌桶限流(5令牌/桶,2/s补充) → Lua原子扣减Redis库存 → 异步落库 → 返回占位订单号")
    @PostMapping("/api/seckill/{productId}")
    public Result<SeckillVO> seckill(@PathVariable Long productId,
                                     Authentication authentication) {
        Long userId = (Long) authentication.getPrincipal();
        return Result.ok(seckillService.doSeckill(userId, productId));
    }
}
