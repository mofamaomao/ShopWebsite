package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.AdminProductRequest;
import com.shop.service.AdminProductService;
import com.shop.vo.AdminProductVO;
import com.shop.vo.PageVO;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@Tag(name = "后台管理-商品")
@RestController
@RequestMapping("/api/admin/products")
@RequiredArgsConstructor
public class AdminProductController {

    private final AdminProductService productService;

    @GetMapping
    public Result<PageVO<AdminProductVO>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) Long categoryId,
            @RequestParam(required = false) Long brandId,
            @RequestParam(required = false) Integer status,
            @RequestParam(required = false) String keyword) {
        return Result.ok(productService.listProducts(page, size, categoryId, brandId, status, keyword));
    }

    @PostMapping
    public Result<AdminProductVO> create(@Valid @RequestBody AdminProductRequest req) {
        return Result.ok(productService.create(req));
    }

    @PutMapping("/{id}")
    public Result<AdminProductVO> update(@PathVariable Long id,
                                         @Valid @RequestBody AdminProductRequest req) {
        return Result.ok(productService.update(id, req));
    }

    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        productService.delete(id);
        return Result.ok(null);
    }

    @PutMapping("/{id}/status")
    public Result<AdminProductVO> toggleStatus(@PathVariable Long id,
                                               @RequestParam int status) {
        return Result.ok(productService.toggleStatus(id, status));
    }
}
