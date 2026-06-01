-- ============================================================
-- Migration: 秒杀字段扩展
-- 对 product 表新增三列，可幂等执行（IF NOT EXISTS 兼容 MySQL 8）
-- 执行方式：mysql -u root -predhat shop_demo < docs/migration_seckill.sql
-- ============================================================

USE shop_demo;

ALTER TABLE `product`
    ADD COLUMN IF NOT EXISTS `is_seckill`    TINYINT        NOT NULL DEFAULT 0    COMMENT '是否秒杀商品 0-否 1-是',
    ADD COLUMN IF NOT EXISTS `seckill_stock` INT            NOT NULL DEFAULT 0    COMMENT '秒杀专属库存（预热到 Redis）',
    ADD COLUMN IF NOT EXISTS `seckill_price` DECIMAL(10, 2)          DEFAULT NULL COMMENT '秒杀价格（NULL 则沿用原价）';

-- 将 id=1 的商品设为秒杀商品（测试用）
UPDATE `product`
SET is_seckill    = 1,
    seckill_stock = 5,
    seckill_price = 4999.00
WHERE id = 1;
