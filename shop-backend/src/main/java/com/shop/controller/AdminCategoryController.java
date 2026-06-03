package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.CategoryRequest;
import com.shop.service.AdminCategoryService;
import com.shop.vo.CategoryVO;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "后台管理-分类")
@RestController
@RequestMapping("/api/admin/categories")
@RequiredArgsConstructor
public class AdminCategoryController {

    private final AdminCategoryService categoryService;

    @GetMapping
    public Result<List<CategoryVO>> tree() {
        return Result.ok(categoryService.getTree());
    }

    @PostMapping
    public Result<CategoryVO> create(@Valid @RequestBody CategoryRequest req) {
        return Result.ok(categoryService.create(req));
    }

    @PutMapping("/{id}")
    public Result<CategoryVO> update(@PathVariable Long id, @Valid @RequestBody CategoryRequest req) {
        return Result.ok(categoryService.update(id, req));
    }

    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        categoryService.delete(id);
        return Result.ok(null);
    }
}
