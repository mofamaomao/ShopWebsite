package com.shop.service.impl;

import com.shop.dto.CartAddRequest;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.service.CartService;
import com.shop.vo.CartItemVO;
import com.shop.vo.CartVO;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class CartServiceImpl implements CartService {

    private final StringRedisTemplate redisTemplate;
    private final ProductMapper productMapper;

    private static final String CART_PREFIX = "cart:";

    @Override
    public void addToCart(Long userId, CartAddRequest req) {
        // HINCRBY 幂等叠加数量
        redisTemplate.opsForHash().increment(
                CART_PREFIX + userId,
                String.valueOf(req.getProductId()),
                req.getQuantity()
        );
    }

    @Override
    public CartVO getCart(Long userId) {
        Map<Object, Object> cartMap = redisTemplate.opsForHash().entries(CART_PREFIX + userId);

        List<CartItemVO> items = new ArrayList<>();
        BigDecimal total = BigDecimal.ZERO;

        for (Map.Entry<Object, Object> entry : cartMap.entrySet()) {
            Long productId = Long.parseLong(entry.getKey().toString());
            int quantity = Integer.parseInt(entry.getValue().toString());

            Product product = productMapper.findById(productId).orElse(null);
            if (product == null) continue;

            BigDecimal subtotal = product.getPrice().multiply(BigDecimal.valueOf(quantity));
            total = total.add(subtotal);

            CartItemVO item = new CartItemVO();
            item.setProductId(productId);
            item.setProductName(product.getName());
            item.setPrice(product.getPrice());
            item.setQuantity(quantity);
            item.setSubtotal(subtotal);
            items.add(item);
        }

        CartVO cart = new CartVO();
        cart.setItems(items);
        cart.setTotal(total);
        return cart;
    }
}
