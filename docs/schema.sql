-- ============================================================
-- ShopWebsite Demo — 全量建表脚本
-- 含 DROP TABLE IF EXISTS，可幂等执行
-- 执行方式：mysql -u root -p < docs/schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS shop_demo
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE shop_demo;

-- 按外键依赖逆序删除
DROP TABLE IF EXISTS `order_item`;
DROP TABLE IF EXISTS `order`;
DROP TABLE IF EXISTS `product`;
DROP TABLE IF EXISTS `user`;

-- ------------------------------------------------------------
-- 用户表
-- ------------------------------------------------------------
CREATE TABLE `user` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `phone`      VARCHAR(20)  NOT NULL COMMENT '手机号（唯一）',
    `password`   VARCHAR(255) NOT NULL COMMENT '密码（BCrypt 加密）',
    `nickname`   VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '昵称',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- ------------------------------------------------------------
-- 商品表
-- ------------------------------------------------------------
CREATE TABLE `product` (
    `id`          BIGINT         NOT NULL AUTO_INCREMENT COMMENT '商品ID',
    `name`        VARCHAR(200)   NOT NULL COMMENT '商品名称',
    `price`       DECIMAL(10, 2) NOT NULL COMMENT '价格（元）',
    `stock`       INT            NOT NULL DEFAULT 0 COMMENT '库存数量',
    `category`    VARCHAR(50)    NOT NULL DEFAULT '' COMMENT '商品分类',
    `image_url`   VARCHAR(500)            DEFAULT NULL COMMENT '封面图片 URL',
    `description` TEXT                    DEFAULT NULL COMMENT '商品描述',
    PRIMARY KEY (`id`),
    KEY `idx_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

-- ------------------------------------------------------------
-- 订单表
-- ------------------------------------------------------------
CREATE TABLE `order` (
    `id`          BIGINT         NOT NULL AUTO_INCREMENT COMMENT '订单ID',
    `user_id`     BIGINT         NOT NULL COMMENT '下单用户ID',
    `total_price` DECIMAL(10, 2) NOT NULL COMMENT '订单总金额',
    `status`      VARCHAR(20)    NOT NULL DEFAULT 'PENDING' COMMENT '状态: PENDING / PAID / CANCELLED',
    `created_at`  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    CONSTRAINT `fk_order_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';

-- ------------------------------------------------------------
-- 订单明细表
-- ------------------------------------------------------------
CREATE TABLE `order_item` (
    `id`         BIGINT         NOT NULL AUTO_INCREMENT COMMENT '明细ID',
    `order_id`   BIGINT         NOT NULL COMMENT '所属订单ID',
    `product_id` BIGINT         NOT NULL COMMENT '商品ID',
    `quantity`   INT            NOT NULL COMMENT '购买数量',
    `price`      DECIMAL(10, 2) NOT NULL COMMENT '下单时快照单价',
    PRIMARY KEY (`id`),
    KEY `idx_order_id` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';
