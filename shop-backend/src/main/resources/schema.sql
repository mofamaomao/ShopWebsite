-- 创建数据库
CREATE DATABASE IF NOT EXISTS shop_demo DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE shop_demo;

-- 用户表
CREATE TABLE IF NOT EXISTS `user` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `phone`      VARCHAR(20)  NOT NULL COMMENT '手机号',
    `password`   VARCHAR(255) NOT NULL COMMENT '密码（BCrypt加密）',
    `nickname`   VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '昵称',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- 商品表
CREATE TABLE IF NOT EXISTS `product` (
    `id`          BIGINT         NOT NULL AUTO_INCREMENT COMMENT '商品ID',
    `name`        VARCHAR(200)   NOT NULL COMMENT '商品名称',
    `price`       DECIMAL(10, 2) NOT NULL COMMENT '价格',
    `stock`       INT            NOT NULL DEFAULT 0 COMMENT '库存',
    `category`    VARCHAR(50)    NOT NULL DEFAULT '' COMMENT '分类',
    `image_url`   VARCHAR(500)   DEFAULT NULL COMMENT '图片URL',
    `description` TEXT           DEFAULT NULL COMMENT '商品描述',
    PRIMARY KEY (`id`),
    KEY `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

-- 订单表
CREATE TABLE IF NOT EXISTS `order` (
    `id`          BIGINT         NOT NULL AUTO_INCREMENT COMMENT '订单ID',
    `user_id`     BIGINT         NOT NULL COMMENT '用户ID',
    `total_price` DECIMAL(10, 2) NOT NULL COMMENT '订单总金额',
    `status`      VARCHAR(20)    NOT NULL DEFAULT 'PENDING' COMMENT '订单状态: PENDING/PAID/CANCELLED',
    `created_at`  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_order_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';
