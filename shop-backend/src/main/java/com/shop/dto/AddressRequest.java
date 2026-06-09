package com.shop.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class AddressRequest {

    @NotBlank(message = "收货人不能为空")
    @Size(max = 10, message = "收货人姓名不超过10字")
    private String receiver;

    @NotBlank(message = "手机号不能为空")
    @Pattern(regexp = "1[3-9]\\d{9}", message = "手机号格式不正确")
    private String phone;

    @NotBlank(message = "省份不能为空")
    private String province;

    @NotBlank(message = "城市不能为空")
    private String city;

    @NotBlank(message = "区/县不能为空")
    private String district;

    @NotBlank(message = "详细地址不能为空")
    @Size(max = 100, message = "详细地址不超过100字")
    private String detail;

    private Boolean isDefault = false;
}
