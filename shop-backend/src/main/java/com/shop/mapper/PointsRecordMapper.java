package com.shop.mapper;

import com.shop.entity.PointsRecord;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;

@Mapper
public interface PointsRecordMapper {

    List<PointsRecord> findByUserId(Long userId);

    int insert(PointsRecord record);

    /** 幂等检查：同一订单同类型是否已记录 */
    boolean existsByOrderIdAndType(@Param("orderId") String orderId, @Param("type") int type);

    /** type=1 获得积分总量 */
    int sumEarned(Long userId);

    /** type=2 消费积分总量（正数返回） */
    int sumUsed(Long userId);
}
