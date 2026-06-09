package com.shop.controller;

import com.shop.common.Result;
import com.shop.dto.AddressRequest;
import com.shop.service.AddressService;
import com.shop.vo.AddressVO;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "收货地址（需登录）")
@RestController
@RequestMapping("/api/user/addresses")
@RequiredArgsConstructor
public class UserAddressController {

    private final AddressService addressService;

    @Operation(summary = "我的地址列表", description = "默认地址排第一")
    @GetMapping
    public Result<List<AddressVO>> list(Authentication auth) {
        return Result.ok(addressService.getUserAddresses(userId(auth)));
    }

    @Operation(summary = "新增地址")
    @PostMapping
    public Result<AddressVO> create(@Valid @RequestBody AddressRequest req,
                                    Authentication auth) {
        return Result.ok(addressService.createAddress(userId(auth), req));
    }

    @Operation(summary = "修改地址")
    @PutMapping("/{id}")
    public Result<AddressVO> update(@PathVariable Long id,
                                    @Valid @RequestBody AddressRequest req,
                                    Authentication auth) {
        return Result.ok(addressService.updateAddress(userId(auth), id, req));
    }

    @Operation(summary = "删除地址")
    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id, Authentication auth) {
        addressService.deleteAddress(userId(auth), id);
        return Result.<Void>ok("已删除", null);
    }

    @Operation(summary = "设为默认地址")
    @PutMapping("/{id}/default")
    public Result<Void> setDefault(@PathVariable Long id, Authentication auth) {
        addressService.setDefaultAddress(userId(auth), id);
        return Result.<Void>ok("已设为默认", null);
    }

    private Long userId(Authentication auth) {
        return (Long) auth.getPrincipal();
    }
}
