package com.shop.vo;

import lombok.Data;

@Data
public class AddressVO {
    private Long id;
    private String receiver;
    private String phone;
    private String province;
    private String city;
    private String district;
    private String detail;
    private Integer isDefault;
}
