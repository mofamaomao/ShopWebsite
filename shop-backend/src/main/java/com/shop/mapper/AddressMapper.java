package com.shop.mapper;

import com.shop.entity.Address;
import org.apache.ibatis.annotations.Mapper;

import java.util.List;
import java.util.Optional;

@Mapper
public interface AddressMapper {

    List<Address> findByUserId(Long userId);

    Optional<Address> findById(Long id);

    int countByUserId(Long userId);

    int insert(Address address);

    int update(Address address);

    int deleteById(Long id);

    int clearDefaultByUserId(Long userId);

    int setDefaultById(Long id);

    /** 删除默认地址后，自动晋升最新创建的剩余地址 */
    Optional<Address> findLatestByUserId(Long userId);
}
