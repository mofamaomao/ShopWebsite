package com.shop.service;

import com.shop.dto.CartAddRequest;
import com.shop.vo.CartVO;

public interface CartService {
    void addToCart(Long userId, CartAddRequest request);
    CartVO getCart(Long userId);
}
