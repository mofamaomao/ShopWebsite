-- M2: 可靠投递 + 幂等消费 DDL
-- 消息投递状态跟踪表，兼容 MySQL 5.7+

CREATE TABLE IF NOT EXISTS `mq_message` (
    `id`          VARCHAR(36)  NOT NULL            COMMENT '消息ID（orderId UUID）',
    `content`     TEXT         NOT NULL            COMMENT 'JSON 序列化的 OrderMessage',
    `status`      TINYINT      NOT NULL DEFAULT 0  COMMENT '0=待投递 1=已投递 2=失败 3=死信',
    `retry_count` INT          NOT NULL DEFAULT 0  COMMENT '重试次数',
    `created_at`  DATETIME     NOT NULL            COMMENT '创建时间',
    `updated_at`  DATETIME     NOT NULL            COMMENT '最后更新时间',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MQ消息投递状态表';
