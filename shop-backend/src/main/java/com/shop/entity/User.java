package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class User {

    private Long id;
    private String phone;
    private String password;
    private String nickname;
    private String role;
    private LocalDateTime createdAt;
    private Integer points;
}
