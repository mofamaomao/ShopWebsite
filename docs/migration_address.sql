-- 执行: mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_address.sql
-- Phase 14: 收货地址模块 (U2)

CREATE TABLE IF NOT EXISTS `address` (
  `id`         BIGINT       PRIMARY KEY AUTO_INCREMENT,
  `user_id`    BIGINT       NOT NULL,
  `receiver`   VARCHAR(20)  NOT NULL,
  `phone`      VARCHAR(11)  NOT NULL,
  `province`   VARCHAR(20)  NOT NULL,
  `city`       VARCHAR(20)  NOT NULL,
  `district`   VARCHAR(20)  NOT NULL,
  `detail`     VARCHAR(200) NOT NULL,
  `is_default` TINYINT      DEFAULT 0,
  `created_at` DATETIME     NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_address_user ON `address`(`user_id`);

ALTER TABLE `order`
  ADD COLUMN IF NOT EXISTS `receiver`     VARCHAR(20)  NULL COMMENT '收货人快照' AFTER `remark`,
  ADD COLUMN IF NOT EXISTS `phone`        VARCHAR(11)  NULL COMMENT '手机号快照' AFTER `receiver`,
  ADD COLUMN IF NOT EXISTS `full_address` VARCHAR(300) NULL COMMENT '完整地址快照' AFTER `phone`;
