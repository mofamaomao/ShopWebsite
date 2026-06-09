package com.shop.controller;

import com.shop.common.Result;
import com.shop.service.PointsService;
import com.shop.vo.PageVO;
import com.shop.vo.PointsBalanceVO;
import com.shop.vo.PointsRecordVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@Tag(name = "积分中心（需登录）")
@RestController
@RequestMapping("/api/user/points")
@RequiredArgsConstructor
public class UserPointsController {

    private final PointsService pointsService;

    @Operation(summary = "积分余额与汇总")
    @GetMapping
    public Result<PointsBalanceVO> balance(Authentication auth) {
        return Result.ok(pointsService.getBalance(userId(auth)));
    }

    @Operation(summary = "积分明细列表")
    @GetMapping("/records")
    public Result<PageVO<PointsRecordVO>> records(
            @RequestParam(defaultValue = "1")  int page,
            @RequestParam(defaultValue = "20") int size,
            Authentication auth) {
        return Result.ok(pointsService.getRecords(userId(auth), page, size));
    }

    private Long userId(Authentication auth) {
        return (Long) auth.getPrincipal();
    }
}
