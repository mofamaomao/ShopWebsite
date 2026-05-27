package com.shop.mapper;

import com.shop.entity.User;
import org.apache.ibatis.annotations.Mapper;

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
}
