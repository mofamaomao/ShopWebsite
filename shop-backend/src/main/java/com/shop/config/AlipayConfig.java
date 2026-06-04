package com.shop.config;

import com.alipay.api.AlipayClient;
import com.alipay.api.DefaultAlipayClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AlipayConfig {

    @Value("${alipay.gateway}")
    private String gateway;

    @Value("${alipay.app-id}")
    private String appId;

    @Value("${alipay.private-key}")
    private String privateKey;

    @Value("${alipay.public-key}")
    private String publicKey;

    @Bean
    public AlipayClient alipayClient() throws Exception {
        return new DefaultAlipayClient(gateway, appId, privateKey, "json", "UTF-8", publicKey, "RSA2");
    }
}
