-- M1: RabbitMQ 异步下单 DDL 变更
-- 为 order 表增加 order_no 字段，作为业务幂等键（UUID）
-- 兼容 MySQL 5.7+

ALTER TABLE `order`
    ADD COLUMN `order_no` VARCHAR(36) NULL COMMENT '业务订单号（UUID）';

-- MySQL 对 UNIQUE 列允许多个 NULL，历史数据保持 NULL 不冲突
ALTER TABLE `order`
    ADD UNIQUE KEY `uk_order_no` (`order_no`);
