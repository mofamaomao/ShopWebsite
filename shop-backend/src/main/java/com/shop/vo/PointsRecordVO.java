package com.shop.vo;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class PointsRecordVO {
    private Long id;
    private Integer type;
    private Integer points;
    private Integer balance;
    private String source;
    private String orderId;
    private LocalDateTime createdAt;
}
