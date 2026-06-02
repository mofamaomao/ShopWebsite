-- M1: RabbitMQ 异步下单 DDL 变更
-- 为 order 表增加 order_no 字段，作为业务幂等键（UUID，UNIQUE）

ALTER TABLE `order`
    ADD COLUMN IF NOT EXISTS `order_no` VARCHAR(36) NOT NULL DEFAULT '' COMMENT '业务订单号（UUID）';

-- 若 DEFAULT '' 临时占位导致重复，先去重再加唯一约束
-- UPDATE `order` SET order_no = UUID() WHERE order_no = '';

ALTER TABLE `order`
    ADD UNIQUE KEY `uk_order_no` (`order_no`);
