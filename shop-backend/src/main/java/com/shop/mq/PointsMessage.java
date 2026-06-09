package com.shop.mq;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.math.BigDecimal;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PointsMessage implements Serializable {
    private String orderId;
    private Long userId;
    /** 实付金额（扣除积分抵扣后），用于计算获得积分 */
    private BigDecimal paidAmount;
}
