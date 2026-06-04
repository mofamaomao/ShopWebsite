package com.shop.service;

import java.math.BigDecimal;
import java.util.Map;

public interface PayService {

    /** 生成支付宝 PC 网页支付表单 HTML */
    String createPayForm(String orderNo, BigDecimal amount, String subject);

    /** 查询支付宝交易状态（TRADE_SUCCESS / WAIT_BUYER_PAY / TRADE_CLOSED 等） */
    String queryPayStatus(String orderNo);

    /**
     * 处理支付宝异步回调：验签 + 幂等更新订单状态
     * @return true=处理成功，响应 "success"；false=验签失败，响应 "failure"
     */
    boolean handleNotify(Map<String, String> params);
}
