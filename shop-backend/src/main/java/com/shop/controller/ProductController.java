package com.shop.controller;

import com.shop.common.Result;
import com.shop.service.ProductService;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@Tag(name = "商品")
@RestController
@RequestMapping("/api/products")
@RequiredArgsConstructor
public class ProductController {

    private final ProductService productService;

    @Operation(summary = "商品列表", description = "分页 + keyword 模糊搜索 name/description")
    @GetMapping
    public Result<PageVO<ProductVO>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "") String keyword) {
        return Result.ok(productService.listProducts(page, size, keyword));
    }

    @Operation(summary = "商品详情")
    @GetMapping("/{id}")
    public Result<ProductVO> get(@PathVariable Long id) {
        return Result.ok(productService.getProduct(id));
    }
}
