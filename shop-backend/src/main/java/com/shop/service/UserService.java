package com.shop.service;

import com.shop.dto.LoginRequest;
import com.shop.dto.RegisterRequest;
import com.shop.vo.LoginVO;

public interface UserService {
    Long register(RegisterRequest request);
    LoginVO login(LoginRequest request);
}
