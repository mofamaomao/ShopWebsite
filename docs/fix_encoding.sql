-- ============================================================
-- 修复分类/品牌/管理员昵称的字符集乱码
-- 原因：migration_admin.sql 在 GBK 默认编码的 MySQL 客户端（中文 Windows）
--       下执行，UTF-8 文件内容被误当 GBK 解析后存入数据库。
--
-- 执行方式（任意系统均可）：
--   mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/fix_encoding.sql
--
-- 说明：本文件所有中文值均使用十六进制字面量 x'...'，
--       不依赖客户端编码，执行结果与操作系统无关。
-- ============================================================

USE shop_demo;

-- ── 分类名称 ──────────────────────────────────────────────
UPDATE `category` SET `name` = x'E6898BE69CBAE695B0E7A081' WHERE id = 1;   -- 手机数码
UPDATE `category` SET `name` = x'E6898BE69CBA'             WHERE id = 2;   -- 手机
UPDATE `category` SET `name` = x'E5B9B3E69DBF'             WHERE id = 3;   -- 平板
UPDATE `category` SET `name` = x'E794B5E88491E58A9EE585AC' WHERE id = 4;   -- 电脑办公
UPDATE `category` SET `name` = x'E7AC94E8AEB0E69CAC'       WHERE id = 5;   -- 笔记本
UPDATE `category` SET `name` = x'E58FB0E5BC8FE69CBA'       WHERE id = 6;   -- 台式机
UPDATE `category` SET `name` = x'E880B3E69CBAE99FB3E5938D' WHERE id = 7;   -- 耳机音响
UPDATE `category` SET `name` = x'E880B3E69CBA'             WHERE id = 8;   -- 耳机
UPDATE `category` SET `name` = x'E5A496E8AEBEE9858DE4BBB6' WHERE id = 9;   -- 外设配件
UPDATE `category` SET `name` = x'E994AEE79B98'             WHERE id = 10;  -- 键盘

-- ── 品牌名称 ──────────────────────────────────────────────
UPDATE `brand` SET `name` = x'E88BB9E69E9C' WHERE id = 1;  -- 苹果
UPDATE `brand` SET `name` = x'E5B08FE7B1B3' WHERE id = 2;  -- 小米
UPDATE `brand` SET `name` = x'E58D8EE4B8BA' WHERE id = 3;  -- 华为
-- id=4 Cherry 为 ASCII，无需修复
UPDATE `brand` SET `name` = x'E7B4A2E5B0BC' WHERE id = 5;  -- 索尼

-- ── 管理员昵称 ────────────────────────────────────────────
UPDATE `user` SET `nickname` = x'E7AEA1E79086E59198' WHERE id = 1000;  -- 管理员

SELECT 'encoding fix done' AS result;
