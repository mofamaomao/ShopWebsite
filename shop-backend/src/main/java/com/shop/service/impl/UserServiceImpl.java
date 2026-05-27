package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.config.JwtUtils;
import com.shop.dto.LoginRequest;
import com.shop.dto.RegisterRequest;
import com.shop.entity.User;
import com.shop.mapper.UserMapper;
import com.shop.service.UserService;
import com.shop.vo.LoginVO;
import com.shop.vo.UserVO;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {

    private final UserMapper userMapper;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtils jwtUtils;

    @Override
    public Long register(RegisterRequest req) {
        if (userMapper.findByPhone(req.getPhone()).isPresent()) {
            throw new BusinessException(ErrorCode.PHONE_EXISTS);
        }
        User user = new User();
        user.setPhone(req.getPhone());
        user.setPassword(passwordEncoder.encode(req.getPassword()));
        user.setNickname(req.getNickname());
        userMapper.insert(user);
        return user.getId();
    }

    @Override
    public LoginVO login(LoginRequest req) {
        User user = userMapper.findByPhone(req.getPhone())
                .orElseThrow(() -> new BusinessException(ErrorCode.PASSWORD_WRONG));
        if (!passwordEncoder.matches(req.getPassword(), user.getPassword())) {
            throw new BusinessException(ErrorCode.PASSWORD_WRONG);
        }
        UserVO userVO = new UserVO();
        userVO.setId(user.getId());
        userVO.setPhone(user.getPhone());
        userVO.setNickname(user.getNickname());
        return new LoginVO(jwtUtils.generateToken(user.getId()), userVO);
    }
}
