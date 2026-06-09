package com.shop.mapper;

import com.shop.entity.User;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Optional;

@Mapper
public interface UserMapper {

    Optional<User> findById(Long id);

    Optional<User> findByPhone(String phone);

    List<User> findAll();

    int insert(User user);

    int update(User user);

    int deleteById(Long id);

    /** 查询当前积分余额 */
    int getPoints(Long userId);

    /** 增加积分（用于发放） */
    int addPoints(@Param("userId") Long userId, @Param("delta") int delta);

    /** 扣减积分（余额不足时返回 0 行，不报错） */
    int deductPoints(@Param("userId") Long userId, @Param("delta") int delta);
}
