package com.shop.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.List;

@Data
public class OrderCreateRequest {

    @NotEmpty(message = "订单商品不能为空")
    private List<OrderItemRequest> items;

    /** 收货地址 ID（可选，不传则不快照地址） */
    private Long addressId;

    /** 是否使用积分抵扣（可选，默认 false） */
    private Boolean usePoints = false;

    @Data
    public static class OrderItemRequest {

        @NotNull(message = "商品ID不能为空")
        private Long productId;

        @NotNull(message = "数量不能为空")
        @Min(value = 1, message = "数量至少为 1")
        private Integer quantity;
    }
}
