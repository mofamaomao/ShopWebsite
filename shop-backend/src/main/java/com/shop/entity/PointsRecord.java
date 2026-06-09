package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class PointsRecord {
    private Long id;
    private Long userId;
    private Integer type;    // 1=获得 2=消费 3=过期
    private Integer points;  // 正数=获得，负数=消费/过期
    private Integer balance; // 变动后余额快照
    private String source;
    private String orderId;
    private LocalDateTime createdAt;
}
