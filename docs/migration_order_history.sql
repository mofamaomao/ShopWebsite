-- 执行: mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_order_history.sql
-- Phase 13: 订单历史模块 — 扩展 order 和 order_item 字段

ALTER TABLE `order`
  ADD COLUMN `pay_time`    DATETIME NULL COMMENT '支付时间'    AFTER `status`,
  ADD COLUMN `cancel_time` DATETIME NULL COMMENT '取消时间'    AFTER `pay_time`,
  ADD COLUMN `remark`      VARCHAR(500) NULL COMMENT '订单备注' AFTER `cancel_time`;

ALTER TABLE `order_item`
  ADD COLUMN `product_name` VARCHAR(200) NOT NULL DEFAULT '' COMMENT '商品名称快照' AFTER `price`,
  ADD COLUMN `product_img`  VARCHAR(500) NOT NULL DEFAULT '' COMMENT '商品图片快照'  AFTER `product_name`,
  ADD COLUMN `subtotal`     DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '小计'      AFTER `product_img`;
