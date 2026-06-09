-- 执行: mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_address.sql
-- Phase 14: 收货地址模块 (U2) — 完全幂等，可重复执行

-- 1. address 表
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

-- 2. address 索引（检查后创建，避免 Duplicate key 错误）
SET @idx = (
  SELECT COUNT(1) FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name   = 'address'
    AND index_name   = 'idx_address_user'
);
SET @sql = IF(@idx = 0,
  'CREATE INDEX idx_address_user ON `address`(`user_id`)',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 3. order 表 receiver 列
SET @col = (
  SELECT COUNT(1) FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name   = 'order'
    AND column_name  = 'receiver'
);
SET @sql = IF(@col = 0,
  'ALTER TABLE `order` ADD COLUMN `receiver` VARCHAR(20) NULL AFTER `remark`',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 4. order 表 phone 列
SET @col = (
  SELECT COUNT(1) FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name   = 'order'
    AND column_name  = 'phone'
);
SET @sql = IF(@col = 0,
  'ALTER TABLE `order` ADD COLUMN `phone` VARCHAR(11) NULL AFTER `receiver`',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 5. order 表 full_address 列
SET @col = (
  SELECT COUNT(1) FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name   = 'order'
    AND column_name  = 'full_address'
);
SET @sql = IF(@col = 0,
  'ALTER TABLE `order` ADD COLUMN `full_address` VARCHAR(300) NULL AFTER `phone`',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
