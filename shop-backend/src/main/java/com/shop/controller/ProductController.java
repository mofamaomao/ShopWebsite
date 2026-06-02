package com.shop.controller;

import com.shop.common.Result;
import com.shop.service.ProductService;
import com.shop.vo.ProductVO;
import com.shop.vo.SearchResultVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;

@Tag(name = "商品")
@RestController
@RequestMapping("/api/products")
@RequiredArgsConstructor
public class ProductController {

    private final ProductService productService;

    @Operation(summary = "商品列表",
               description = "有 keyword/category/price/sort → ES 查询（含高亮+分类聚合）; 无任何筛选 → MySQL 全量分页; source=mysql → 强制 MySQL")
    @GetMapping
    public Result<SearchResultVO> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "") String keyword,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) BigDecimal minPrice,
            @RequestParam(required = false) BigDecimal maxPrice,
            @RequestParam(defaultValue = "") String sort,
            @RequestParam(defaultValue = "") String source) {
        return Result.ok(productService.listProducts(page, size, keyword,
                category, minPrice, maxPrice, sort, source));
    }

    @Operation(summary = "商品详情")
    @GetMapping("/{id}")
    public Result<ProductVO> get(@PathVariable Long id) {
        return Result.ok(productService.getProduct(id));
    }
}
