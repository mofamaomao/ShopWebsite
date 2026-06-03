package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.BrandRequest;
import com.shop.service.AdminBrandService;
import com.shop.vo.BrandVO;
import com.shop.vo.PageVO;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "后台管理-品牌")
@RestController
@RequestMapping("/api/admin/brands")
@RequiredArgsConstructor
public class AdminBrandController {

    private final AdminBrandService brandService;

    @GetMapping("/all")
    public Result<List<BrandVO>> listAll() {
        return Result.ok(brandService.listAll());
    }

    @GetMapping
    public Result<PageVO<BrandVO>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String keyword) {
        return Result.ok(brandService.listPage(page, size, keyword));
    }

    @PostMapping
    public Result<BrandVO> create(@Valid @RequestBody BrandRequest req) {
        return Result.ok(brandService.create(req));
    }

    @PutMapping("/{id}")
    public Result<BrandVO> update(@PathVariable Long id, @Valid @RequestBody BrandRequest req) {
        return Result.ok(brandService.update(id, req));
    }

    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        brandService.delete(id);
        return Result.ok(null);
    }
}
