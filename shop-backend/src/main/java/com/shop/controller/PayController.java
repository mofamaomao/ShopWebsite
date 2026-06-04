package com.shop.controller;

import com.shop.common.BusinessException;
import com.shop.common.Result;
import com.shop.entity.Order;
import com.shop.mapper.OrderMapper;
import com.shop.service.PayService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@Tag(name = "支付宝支付")
@RestController
@RequestMapping("/api/pay")
@RequiredArgsConstructor
public class PayController {

    private final PayService payService;
    private final OrderMapper orderMapper;

    @Value("${alipay.return-url:http://localhost:5173/order-success}")
    private String frontendReturnUrl;

    /** 发起支付：校验订单归属 + 状态，以服务端金额为准 */
    @Operation(summary = "发起支付宝支付，返回收银台表单 HTML")
    @PostMapping("/create")
    public Result<Map<String, String>> create(@RequestBody Map<String, String> body,
                                               Authentication auth) {
        String orderNo = body.get("orderId");
        Order order = orderMapper.findByOrderNo(orderNo)
                .orElseThrow(() -> new BusinessException(404, "订单不存在"));
        if (!order.getUserId().equals((Long) auth.getPrincipal())) {
            throw new BusinessException(403, "无权访问该订单");
        }
        if (!"PENDING_PAYMENT".equals(order.getStatus())) {
            throw new BusinessException(400, "订单状态不允许支付，当前: " + order.getStatus());
        }
        // 金额以服务端订单为准，不信任前端
        String payForm = payService.createPayForm(
                order.getOrderNo(), order.getTotalPrice(), "ShopDemo-" + orderNo);
        return Result.ok(Map.of("payForm", payForm));
    }

    /** 查询支付结果，TRADE_SUCCESS 时同步更新 DB */
    @Operation(summary = "查询支付结果，前端每 3 秒轮询一次")
    @GetMapping("/query/{orderId}")
    public Result<Map<String, String>> query(@PathVariable String orderId,
                                              Authentication auth) {
        Order order = orderMapper.findByOrderNo(orderId)
                .orElseThrow(() -> new BusinessException(404, "订单不存在"));
        if (!order.getUserId().equals((Long) auth.getPrincipal())) {
            throw new BusinessException(403, "无权访问该订单");
        }
        // 已 PAID 则直接返回，无需调支付宝
        if ("PAID".equals(order.getStatus())) {
            return Result.ok(Map.of("status", "TRADE_SUCCESS"));
        }
        String alipayStatus = payService.queryPayStatus(orderId);
        if ("TRADE_SUCCESS".equals(alipayStatus)) {
            Order upd = new Order();
            upd.setId(order.getId());
            upd.setStatus("PAID");
            orderMapper.update(upd);
        }
        return Result.ok(Map.of("status", alipayStatus != null ? alipayStatus : "WAIT_BUYER_PAY"));
    }

    /**
     * 支付宝异步回调（POST）。
     * 不需要 JWT，已在 SecurityConfig 中放行。
     * 必须返回纯文本 "success" / "failure"，不是 JSON。
     */
    @Operation(summary = "支付宝异步回调（内部，无需鉴权）")
    @PostMapping(value = "/notify", produces = MediaType.TEXT_PLAIN_VALUE)
    public String notify(HttpServletRequest request) {
        Map<String, String> params = new HashMap<>();
        request.getParameterMap().forEach((k, v) -> params.put(k, v[0]));
        boolean ok = payService.handleNotify(params);
        return ok ? "success" : "failure";
    }

    /**
     * 支付宝同步回调（GET）。
     * 同步回调不可信（用户可能伪造），只做页面跳转；
     * 真实支付结果以异步通知为准。
     */
    @Operation(summary = "支付宝同步回调（重定向到前端，无需鉴权）")
    @GetMapping("/return")
    public void returnCallback(@RequestParam(required = false) String out_trade_no,
                                HttpServletResponse response) throws Exception {
        String url = frontendReturnUrl
                + (out_trade_no != null ? "?orderId=" + out_trade_no : "");
        response.sendRedirect(url);
    }
}
