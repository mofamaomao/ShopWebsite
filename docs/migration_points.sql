-- 执行: mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_points.sql
-- Phase 15: 积分系统 (U3) — 完全幂等，可重复执行

-- 1. points_record 表
CREATE TABLE IF NOT EXISTS `points_record` (
  `id`         BIGINT      PRIMARY KEY AUTO_INCREMENT,
  `user_id`    BIGINT      NOT NULL,
  `type`       TINYINT     NOT NULL,   -- 1=获得 2=消费 3=过期
  `points`     INT         NOT NULL,   -- 正数=获得，负数=消费/过期
  `balance`    INT         NOT NULL,   -- 变动后余额快照
  `source`     VARCHAR(50) NOT NULL,
  `order_id`   VARCHAR(36),
  `created_at` DATETIME    NOT NULL
);

-- 2. points_record 索引
SET @idx = (
  SELECT COUNT(1) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'points_record' AND index_name = 'idx_points_user'
);
SET @sql = IF(@idx = 0,
  'CREATE INDEX idx_points_user ON `points_record`(`user_id`)',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- 3. user 表增加 points 列
SET @col = (
  SELECT COUNT(1) FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'user' AND column_name = 'points'
);
SET @sql = IF(@col = 0,
  'ALTER TABLE `user` ADD COLUMN `points` INT DEFAULT 0',
  'SELECT 1'
);
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
