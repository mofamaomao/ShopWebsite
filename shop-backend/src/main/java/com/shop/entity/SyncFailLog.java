package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class SyncFailLog {
    private Long id;
    private Long productId;
    private String operation;
    private String errorMsg;
    private LocalDateTime createdAt;
}
