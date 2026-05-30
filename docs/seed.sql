-- ============================================================
-- ShopWebsite Demo — 商品种子数据
-- 12 条，覆盖 6 个分类和低/中/高三个价格区间
-- 执行方式：mysql -u root -p shop_demo < docs/seed.sql
-- ============================================================

USE shop_demo;

INSERT INTO `product` (id, name, price, stock, category, description) VALUES
-- 手机（高价）
(1,  'iPhone 15 Pro',           9999.00, 100, '手机', '苹果旗舰，A17 Pro 芯片，钛金属边框，支持 USB-C'),
(2,  '小米14',                  3999.00, 200, '手机', '小米旗舰，骁龙 8 Gen3，徕卡光学，120W 快充'),
(3,  'Samsung Galaxy S24 Ultra',8999.00,  80, '手机', '三星旗舰，S Pen 内置，2亿像素摄像头'),

-- 电脑（高价）
(4,  'MacBook Pro 14',         14999.00,  50, '电脑', 'M3 Pro 芯片，16GB 内存，1TB SSD，专业创作利器'),
(5,  'ThinkPad X1 Carbon',      9999.00,  60, '电脑', '超薄商务本，Intel Core Ultra 7，2K 屏，约 1.12 kg'),

-- 耳机（中低价）
(6,  'AirPods Pro 2',           1899.00, 300, '耳机', '苹果主动降噪，自适应音频，H2 芯片，MagSafe 充电盒'),
(7,  'Sony WH-1000XM5',         2199.00, 150, '耳机', '索尼旗舰降噪，30 小时续航，多设备快速切换'),

-- 外设（低中价）
(8,  '机械键盘 Cherry MX',        599.00, 150, '外设', 'Cherry 红轴，RGB 背光，全铝外壳，PBT 键帽'),
(9,  '罗技 G502 X PLUS',          799.00, 200, '外设', '无线游戏鼠标，LIGHTFORCE 混合微动，25K 传感器'),
(10, '小米显示器 27" 4K',         1999.00, 120, '外设', '27英寸 IPS，3840×2160，100% sRGB，USB-C 65W 反向充电'),

-- 平板（中高价）
(11, 'iPad Pro 12.9 M4',        8999.00,  70, '平板', '苹果平板旗舰，M4 芯片，超视网膜 XDR 屏，支持 Apple Pencil Pro'),
(12, '小米平板6 Pro',            2499.00, 180, '平板', '骁龙 8 Gen2，144Hz 高刷，10000mAh 大电池，33W 快充')
ON DUPLICATE KEY UPDATE
    name        = VALUES(name),
    price       = VALUES(price),
    stock       = VALUES(stock),
    category    = VALUES(category),
    description = VALUES(description);
