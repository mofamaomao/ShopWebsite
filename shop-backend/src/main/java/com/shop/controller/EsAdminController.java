package com.shop.controller;

import com.shop.common.Result;
import com.shop.mapper.ProductMapper;
import com.shop.service.ProductSearchService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/es")
@RequiredArgsConstructor
public class EsAdminController {

    private final ProductMapper productMapper;
    private final ProductSearchService productSearchService;

    @PostMapping("/init")
    public Result<Integer> init() {
        int count = productSearchService.bulkInit(productMapper.findAll());
        return Result.ok(count);
    }
}
