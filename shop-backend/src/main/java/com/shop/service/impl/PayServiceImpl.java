package com.shop.service.impl;

import com.alipay.api.AlipayClient;
import com.alipay.api.internal.util.AlipaySignature;
import com.alipay.api.request.AlipayTradePagePayRequest;
import com.alipay.api.request.AlipayTradeQueryRequest;
import com.alipay.api.response.AlipayTradePagePayResponse;
import com.alipay.api.response.AlipayTradeQueryResponse;
import com.shop.common.PayException;
import com.shop.entity.Order;
import com.shop.mapper.OrderMapper;
import com.shop.service.PayService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class PayServiceImpl implements PayService {

    @Autowired(required = false)
    private AlipayClient alipayClient;

    private final OrderMapper orderMapper;

    @Value("${alipay.public-key:}")
    private String alipayPublicKey;

    @Value("${alipay.return-url:http://localhost:5173/order-success}")
    private String returnUrl;

    @Value("${alipay.notify-url:http://localhost:8080/api/pay/notify}")
    private String notifyUrl;

    private void checkAlipayConfigured() {
        if (alipayClient == null) {
            throw new PayException("支付宝未配置，请设置 ALIPAY_APP_ID / ALIPAY_PRIVATE_KEY / ALIPAY_PUBLIC_KEY 环境变量后重启服务");
        }
    }

    @Override
    public String createPayForm(String orderNo, BigDecimal amount, String subject) {
        checkAlipayConfigured();
        AlipayTradePagePayRequest request = new AlipayTradePagePayRequest();
        request.setReturnUrl(returnUrl);
        request.setNotifyUrl(notifyUrl);
        request.setBizContent(String.format(
                "{\"out_trade_no\":\"%s\",\"total_amount\":\"%s\"," +
                "\"subject\":\"%s\",\"product_code\":\"FAST_INSTANT_TRADE_PAY\"}",
                orderNo, amount.toPlainString(), subject));
        try {
            AlipayTradePagePayResponse response = alipayClient.pageExecute(request);
            if (!response.isSuccess()) {
                log.error("支付表单生成失败: code={} msg={}", response.getCode(), response.getSubMsg());
                throw new PayException("支付表单生成失败: " + response.getSubMsg());
            }
            log.info("支付表单生成成功, orderNo={}", orderNo);
            return response.getBody();
        } catch (PayException e) {
            throw e;
        } catch (Exception e) {
            log.error("支付服务异常: {}", e.getMessage(), e);
            throw new PayException("支付服务异常: " + e.getMessage());
        }
    }

    @Override
    public String queryPayStatus(String orderNo) {
        checkAlipayConfigured();
        AlipayTradeQueryRequest request = new AlipayTradeQueryRequest();
        request.setBizContent(String.format("{\"out_trade_no\":\"%s\"}", orderNo));
        try {
            AlipayTradeQueryResponse response = alipayClient.execute(request);
            if (!response.isSuccess()) {
                log.debug("支付宝查询未返回成功: orderNo={} msg={}", orderNo, response.getSubMsg());
                return "WAIT_BUYER_PAY";
            }
            return response.getTradeStatus();
        } catch (Exception e) {
            log.error("查询支付状态异常: orderNo={} err={}", orderNo, e.getMessage());
            return "WAIT_BUYER_PAY";
        }
    }

    @Override
    public boolean handleNotify(Map<String, String> params) {
        try {
            // ① 验签（安全红线，不可跳过）
            boolean signVerified = AlipaySignature.rsaCheckV1(params, alipayPublicKey, "UTF-8", "RSA2");
            if (!signVerified) {
                log.warn("支付回调验签失败, orderNo={}", params.get("out_trade_no"));
                return false;
            }
            log.info("支付回调验签成功, orderNo={}, tradeStatus={}",
                    params.get("out_trade_no"), params.get("trade_status"));

            // ② 只处理 TRADE_SUCCESS
            if (!"TRADE_SUCCESS".equals(params.get("trade_status"))) {
                return true;
            }

            // ③ 幂等：已 PAID 则直接返回 success
            String orderNo = params.get("out_trade_no");
            Order order = orderMapper.findByOrderNo(orderNo).orElse(null);
            if (order == null) {
                log.warn("支付回调：订单不存在, orderNo={}", orderNo);
                return true;
            }
            if ("PAID".equals(order.getStatus())) {
                log.info("支付回调：订单已支付，幂等跳过, orderNo={}", orderNo);
                return true;
            }

            // ④ 更新订单状态
            Order upd = new Order();
            upd.setId(order.getId());
            upd.setStatus("PAID");
            orderMapper.update(upd);
            log.info("订单状态已更新为 PAID, orderNo={}", orderNo);
            return true;

        } catch (Exception e) {
            log.error("支付回调处理异常: {}", e.getMessage(), e);
            return false;
        }
    }
}
