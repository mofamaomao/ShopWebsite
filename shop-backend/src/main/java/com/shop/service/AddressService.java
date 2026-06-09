package com.shop.service;

import com.shop.dto.AddressRequest;
import com.shop.vo.AddressVO;

import java.util.List;

public interface AddressService {

    List<AddressVO> getUserAddresses(Long userId);

    AddressVO createAddress(Long userId, AddressRequest req);

    AddressVO updateAddress(Long userId, Long id, AddressRequest req);

    void deleteAddress(Long userId, Long id);

    void setDefaultAddress(Long userId, Long id);
}
