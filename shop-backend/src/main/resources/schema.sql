-- 创建数据库
CREATE DATABASE IF NOT EXISTS shop_demo DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE shop_demo;

-- 用户表
CREATE TABLE IF NOT EXISTS `user` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '用户ID',
    `phone`      VARCHAR(20)  NOT NULL COMMENT '手机号',
    `password`   VARCHAR(255) NOT NULL COMMENT '密码（BCrypt加密）',
    `nickname`   VARCHAR(50)  NOT NULL DEFAULT '' COMMENT '昵称',
    `role`       VARCHAR(20)  NOT NULL DEFAULT 'USER' COMMENT '角色：USER/ADMIN',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- 商品分类表
CREATE TABLE IF NOT EXISTS `category` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '分类ID',
    `name`       VARCHAR(50)  NOT NULL COMMENT '分类名称',
    `parent_id`  BIGINT       DEFAULT NULL COMMENT '父分类ID，NULL 表示一级',
    `sort`       INT          NOT NULL DEFAULT 0 COMMENT '排序（升序）',
    `icon_url`   VARCHAR(500) DEFAULT NULL COMMENT '图标URL',
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_parent_id` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品分类';

-- 品牌表
CREATE TABLE IF NOT EXISTS `brand` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '品牌ID',
    `name`        VARCHAR(50)  NOT NULL COMMENT '品牌名称',
    `logo_url`    VARCHAR(500) DEFAULT NULL COMMENT 'Logo URL',
    `description` TEXT         DEFAULT NULL COMMENT '品牌描述',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='品牌';

-- 商品表
CREATE TABLE IF NOT EXISTS `product` (
    `id`          BIGINT         NOT NULL AUTO_INCREMENT COMMENT '商品ID',
    `name`        VARCHAR(200)   NOT NULL COMMENT '商品名称',
    `price`       DECIMAL(10, 2) NOT NULL COMMENT '价格',
    `stock`       INT            NOT NULL DEFAULT 0 COMMENT '库存',
    `category`    VARCHAR(50)    NOT NULL DEFAULT '' COMMENT '分类（旧字段）',
    `image_url`   VARCHAR(500)   DEFAULT NULL COMMENT '图片URL',
    `description` TEXT           DEFAULT NULL COMMENT '商品描述',
    `brand_id`    BIGINT         DEFAULT NULL COMMENT '品牌ID',
    `category_id` BIGINT         DEFAULT NULL COMMENT '分类ID',
    `status`      TINYINT        NOT NULL DEFAULT 1 COMMENT '状态: 0下架 1上架 2草稿',
    `is_deleted`  TINYINT        NOT NULL DEFAULT 0 COMMENT '软删除: 0正常 1已删除',
    PRIMARY KEY (`id`),
    KEY `idx_category` (`category`),
    KEY `idx_category_id` (`category_id`),
    KEY `idx_brand_id` (`brand_id`)
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

-- 订单明细表
CREATE TABLE IF NOT EXISTS `order_item` (
    `id`         BIGINT         NOT NULL AUTO_INCREMENT COMMENT '明细ID',
    `order_id`   BIGINT         NOT NULL COMMENT '订单ID',
    `product_id` BIGINT         NOT NULL COMMENT '商品ID',
    `quantity`   INT            NOT NULL COMMENT '购买数量',
    `price`      DECIMAL(10, 2) NOT NULL COMMENT '下单时单价',
    PRIMARY KEY (`id`),
    KEY `idx_order_id` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';

-- 分类种子数据
INSERT IGNORE INTO `category` (id, name, parent_id, sort) VALUES
(1,  '手机数码',    NULL, 1),
(2,  '手机',       1,    1),
(3,  '平板',       1,    2),
(4,  '电脑办公',    NULL, 2),
(5,  '笔记本',     4,    1),
(6,  '台式机',     4,    2),
(7,  '耳机音响',    NULL, 3),
(8,  '耳机',       7,    1),
(9,  '外设配件',    NULL, 4),
(10, '键盘',       9,    1);

-- 品牌种子数据
INSERT IGNORE INTO `brand` (id, name) VALUES
(1, '苹果'), (2, '小米'), (3, '华为'), (4, 'Cherry'), (5, '索尼');

-- 商品种子数据
INSERT IGNORE INTO `product` (id, name, price, stock, category, description, category_id, brand_id, status) VALUES
(1, 'iPhone 15 Pro',      9999.00, 100, '手机', '苹果旗舰手机，A17 Pro 芯片', 2,  1, 1),
(2, '小米14',             3999.00, 200, '手机', '小米旗舰，骁龙8Gen3',        2,  2, 1),
(3, 'MacBook Pro 14',    14999.00,  50, '电脑', 'M3 Pro 芯片，专业创作利器',  5,  1, 1),
(4, 'AirPods Pro',        1899.00, 300, '耳机', '主动降噪，空间音频',          8,  1, 1),
(5, '机械键盘 Cherry MX',  599.00, 150, '外设', 'Cherry 红轴，RGB 背光',     10,  4, 1);

-- 管理员账号（密码：admin123）
INSERT IGNORE INTO `user` (id, phone, password, nickname, role, created_at)
VALUES (1000, 'admin', '$2a$10$ZuAbg6gP5ltGgUnokc4iKeZhTTBgHCLEhSYMiwrT.GKaBG6sGhO7K', '管理员', 'ADMIN', NOW());
