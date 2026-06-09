# Phase 14 — 收货地址模块（U2）

## 目标

为用户中心增加收货地址管理功能，并将地址快照写入订单，实现：
- 用户可增删改查收货地址（上限 20 条，默认地址唯一）
- 购物车结算时选择收货地址
- 下单时将 receiver / phone / fullAddress 快照到订单表，历史订单地址永久保留
- 订单详情显示收货信息

---

## 数据库变更

### 新增 address 表

```sql
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
```

### order 表扩列

```sql
ALTER TABLE `order`
  ADD COLUMN `receiver`     VARCHAR(20)  NULL,
  ADD COLUMN `phone`        VARCHAR(11)  NULL,
  ADD COLUMN `full_address` VARCHAR(300) NULL;
```

迁移脚本：`docs/migration_address.sql`（使用 information_schema 做幂等检查，兼容 MySQL 5.7/8.x，可重复执行）

---

## 后端实现

### 新增文件

| 文件 | 说明 |
|------|------|
| `entity/Address.java` | id / userId / receiver / phone / province / city / district / detail / isDefault / createdAt |
| `dto/AddressRequest.java` | @NotBlank 全字段校验；phone @Pattern(`1[3-9]\d{9}`) |
| `vo/AddressVO.java` | 返回给前端的视图对象 |
| `mapper/AddressMapper.java` | 7 个方法接口 |
| `resources/mapper/AddressMapper.xml` | findByUserId（默认排第一）/ insert / update / deleteById / clearDefaultByUserId / setDefaultById / findLatestByUserId |
| `service/AddressService.java` | 接口定义 |
| `service/impl/AddressServiceImpl.java` | 业务逻辑（见下） |
| `controller/UserAddressController.java` | 5 个端点，JWT 鉴权 |

### AddressServiceImpl 关键逻辑

- **createAddress**：count ≥ 20 → BusinessException(400)；第一条地址或 isDefault=true 时 clearDefaultByUserId + setDefault 在同一 @Transactional 内执行
- **updateAddress**：findAndValidate 校验归属；isDefault=true 时先 clearDefault
- **deleteAddress**：deleteById 后若被删地址是默认，findLatestByUserId → setDefaultById 自动晋升
- **setDefaultAddress**：clearDefaultByUserId + setDefaultById 同事务，保证唯一默认

### 改动文件

| 文件 | 改动 |
|------|------|
| `dto/OrderCreateRequest.java` | 新增 `Long addressId` 字段（可选） |
| `entity/Order.java` | 新增 receiver / phone / fullAddress 字段 |
| `vo/OrderDetailVO.java` | 新增 receiver / phone / fullAddress |
| `resources/mapper/OrderMapper.xml` | ResultMap / INSERT / UPDATE 补全三列 |
| `mq/OrderMessage.java` | 顶层新增 receiver / phone / fullAddress（用 setter 赋值，避免 @AllArgsConstructor 破坏兼容） |
| `service/impl/OrderServiceImpl.java` | Step 0 按 addressId 查地址并校验归属，快照三字段到 OrderMessage |
| `service/impl/OrderPersistServiceImpl.java` | 写 Order 时透传 receiver / phone / fullAddress |
| `service/impl/UserOrderServiceImpl.java` | getUserOrderDetail 将三字段写入 OrderDetailVO |

---

## 前端实现

### 新增文件

| 文件 | 说明 |
|------|------|
| `src/api/address.js` | getUserAddresses / createAddress / updateAddress / deleteAddress / setDefaultAddress |
| `src/assets/pca.json` | 34 省完整省市区 JSON（el-cascader 数据源，label+value 结构） |
| `src/views/UserAddressesView.vue` | 地址列表 + 新增/编辑弹窗 + 删除确认 |

### UserAddressesView.vue 要点

- el-card 列表，默认地址显示绿色"默认"标签，排在最前
- el-popconfirm 二次确认删除
- el-dialog 表单：收货人 / 手机号 / 省市区（el-cascader + pca.json）/ 详细地址 / 是否默认
- 编辑时 region 回填 `[addr.province, addr.city, addr.district]`
- 保存时拆分 `form.region[0/1/2]` → province / city / district

### 改动文件

| 文件 | 改动 |
|------|------|
| `src/router/index.js` | 新增 `/user/addresses`（requiresAuth: true）|
| `src/components/NavBar.vue` | 登录后显示"地址管理"导航链接 |
| `src/views/CartView.vue` | 去结算 → 弹出地址选择对话框（默认地址预选）；无地址引导跳转；确认下单携带 addressId |
| `src/views/UserOrdersView.vue` | **修复** `res.data.list`/`res.data.total` → `res.list`/`res.total`（HTTP 拦截器已解包，`.data` 多余）；**修复** `detailOrder = res.data` → `res`；详情弹窗增加收货人 / 手机号 / 收货地址行 |

---

## Bug 修复（顺带）

| Bug | 原因 | 修复 |
|-----|------|------|
| 我的订单列表始终为空 | `res.data.list` 中 `res.data` 为 undefined，抛 TypeError 被 finally 吞掉 | 改为 `res.list` / `res.total` |
| 订单详情弹窗无内容 | `detailOrder.value = res.data`，res.data 为 undefined | 改为 `detailOrder.value = res` |

---

## 已知约束

| 约束 | 说明 |
|------|------|
| addressId 可选 | 不传 addressId 时快照字段为 null，历史订单无地址信息属正常情况 |
| 地址快照原则 | 只快照文字，不存 addressId FK，修改/删除地址不影响历史订单 |
| 手机号格式 | 前后端双重校验：前端 el-form @Pattern，后端 @Pattern(`1[3-9]\d{9}`) |
| 地址上限 | 20 条/用户，超出返回 code=400 |

---

## 迁移执行方法

```bash
mysql -u root -p --default-character-set=utf8mb4 shop_demo < docs/migration_address.sql
```

脚本使用 information_schema 做逐项检查，支持重复执行不报错，兼容 MySQL 5.7 / 8.x 全版本。
