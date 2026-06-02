-- Migration: ES sync failure log table
-- Execute: mysql -u root -predhat shop_demo < docs/migration_es.sql

USE shop_demo;

CREATE TABLE IF NOT EXISTS `sync_fail_log` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `product_id` BIGINT       NOT NULL,
    `operation`  VARCHAR(20)  NOT NULL COMMENT 'SAVE or DELETE',
    `error_msg`  VARCHAR(500) DEFAULT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_product_id` (`product_id`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;
