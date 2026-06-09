package com.shop.vo;

import lombok.Data;

@Data
public class PointsBalanceVO {
    private Integer balance;
    private Integer totalEarned;
    private Integer totalUsed;
    /** 供前端计算：100 积分 = 1 元 */
    private Integer redeemRate;
    /** 供前端计算：每笔最多抵扣比例 */
    private Double maxRedeemPct;
}
