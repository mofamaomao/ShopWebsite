package com.shop.mapper;

import com.shop.entity.SyncFailLog;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface SyncFailLogMapper {

    @Insert("INSERT INTO sync_fail_log (product_id, operation, error_msg, created_at) " +
            "VALUES (#{productId}, #{operation}, #{errorMsg}, #{createdAt})")
    int insert(SyncFailLog log);
}
