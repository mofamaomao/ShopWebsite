package com.shop.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class MqMessage {
    public static final int STATUS_PENDING   = 0;
    public static final int STATUS_DELIVERED = 1;
    public static final int STATUS_FAILED    = 2;
    public static final int STATUS_DEAD      = 3;

    private String        id;          // orderId (UUID)
    private String        content;     // JSON of OrderMessage
    private Integer       status;
    private Integer       retryCount;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
