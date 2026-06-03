-- ============================================================
-- Admin 后台管理功能迁移
-- ============================================================

USE shop_demo;

-- 1. 用户表增加角色字段
ALTER TABLE `user`
    ADD COLUMN `role` VARCHAR(20) NOT NULL DEFAULT 'USER' COMMENT '角色：USER / ADMIN';

-- 2. 商品分类表
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

-- 3. 品牌表
CREATE TABLE IF NOT EXISTS `brand` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '品牌ID',
    `name`        VARCHAR(50)  NOT NULL COMMENT '品牌名称',
    `logo_url`    VARCHAR(500) DEFAULT NULL COMMENT 'Logo URL',
    `description` TEXT         DEFAULT NULL COMMENT '品牌描述',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='品牌';

-- 4. 商品表扩展字段
ALTER TABLE `product`
    ADD COLUMN `brand_id`    BIGINT  DEFAULT NULL COMMENT '品牌ID',
    ADD COLUMN `category_id` BIGINT  DEFAULT NULL COMMENT '分类ID',
    ADD COLUMN `status`      TINYINT NOT NULL DEFAULT 1 COMMENT '状态: 0下架 1上架 2草稿',
    ADD COLUMN `is_deleted`  TINYINT NOT NULL DEFAULT 0 COMMENT '软删除: 0正常 1已删除';

-- 5. 种子数据 – 分类
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

-- 6. 种子数据 – 品牌
INSERT IGNORE INTO `brand` (id, name) VALUES
(1, '苹果'),
(2, '小米'),
(3, '华为'),
(4, 'Cherry'),
(5, '索尼');

-- 7. 关联已有商品
UPDATE `product` SET category_id=2, brand_id=1 WHERE id=1;  -- iPhone 15 Pro
UPDATE `product` SET category_id=2, brand_id=2 WHERE id=2;  -- 小米14
UPDATE `product` SET category_id=5, brand_id=1 WHERE id=3;  -- MacBook Pro
UPDATE `product` SET category_id=8, brand_id=1 WHERE id=4;  -- AirPods Pro
UPDATE `product` SET category_id=10,brand_id=4 WHERE id=5;  -- 机械键盘

-- 8. 管理员账号（密码：admin123）
INSERT IGNORE INTO `user` (id, phone, password, nickname, role, created_at)
VALUES (1000, 'admin', '$2a$10$ZuAbg6gP5ltGgUnokc4iKeZhTTBgHCLEhSYMiwrT.GKaBG6sGhO7K', '管理员', 'ADMIN', NOW());
