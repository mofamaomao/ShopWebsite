package com.shop.mq;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class OrderMessage implements Serializable {

    /** Producer 端预生成的 UUID，Consumer 写库时作为 order_no，保证幂等 */
    private String orderId;
    private Long userId;
    private List<Item> items;
    private LocalDateTime createTime;
    /** 收货地址快照（下单时写入，允许为 null） */
    private String receiver;
    private String phone;
    private String fullAddress;
    /** 积分抵扣：待扣积分数（0 = 不使用积分） */
    private Integer usablePoints = 0;
    /** 积分抵扣金额（元），Consumer 将从 totalPrice 中扣除 */
    private BigDecimal pointsDeduction = BigDecimal.ZERO;

    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Item {
        private Long productId;
        private Integer quantity;
        /** 下单时的价格快照，Consumer 不再重查 */
        private BigDecimal price;
        /** 商品名称快照 */
        private String productName;
        /** 商品图片快照 */
        private String productImg;
    }
}
