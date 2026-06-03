package com.shop.mapper;

import com.shop.entity.MqMessage;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface MqMessageMapper {
    int insert(MqMessage msg);
    int updateStatus(@Param("id") String id, @Param("status") int status);
    int markFailed(String id);         // status=2, retry_count++
    int markDead(String id);           // status=3
    List<MqMessage> findForRetry();    // status=2 AND retry_count < 3
}
