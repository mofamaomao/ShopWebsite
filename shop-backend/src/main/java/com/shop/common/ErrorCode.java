package com.shop.common;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public enum ErrorCode {

    SUCCESS(200, "success"),
    BAD_REQUEST(400, "请求参数错误"),
    UNAUTHORIZED(401, "未登录或 token 已过期"),
    NOT_FOUND(404, "资源不存在"),
    INTERNAL_ERROR(500, "服务器内部错误"),
    PHONE_EXISTS(1001, "手机号已被注册"),
    PASSWORD_WRONG(1002, "手机号或密码错误"),
    STOCK_INSUFFICIENT(1003, "库存不足"),
    PRODUCT_NOT_FOUND(1004, "商品不存在"),
    SECKILL_STOCK_EMPTY(1005, "库存不足，手慢了");

    private final int code;
    private final String msg;
}
