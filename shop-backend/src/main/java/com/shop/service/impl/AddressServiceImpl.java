package com.shop.service.impl;

import com.shop.common.BusinessException;
import com.shop.dto.AddressRequest;
import com.shop.entity.Address;
import com.shop.mapper.AddressMapper;
import com.shop.service.AddressService;
import com.shop.vo.AddressVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class AddressServiceImpl implements AddressService {

    private final AddressMapper addressMapper;

    @Override
    public List<AddressVO> getUserAddresses(Long userId) {
        return addressMapper.findByUserId(userId).stream()
                .map(this::toVO).collect(Collectors.toList());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AddressVO createAddress(Long userId, AddressRequest req) {
        int count = addressMapper.countByUserId(userId);
        if (count >= 20) {
            throw new BusinessException(400, "地址数量已达上限（20条）");
        }
        // 第一条地址或显式要求默认，则清除其他默认并置为默认
        boolean setDefault = Boolean.TRUE.equals(req.getIsDefault()) || count == 0;
        if (setDefault) {
            addressMapper.clearDefaultByUserId(userId);
        }

        Address addr = buildAddress(userId, req);
        addr.setIsDefault(setDefault ? 1 : 0);
        addressMapper.insert(addr);
        log.info("[Address] created id={} userId={}", addr.getId(), userId);
        return toVO(addr);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public AddressVO updateAddress(Long userId, Long id, AddressRequest req) {
        findAndValidate(userId, id);

        if (Boolean.TRUE.equals(req.getIsDefault())) {
            addressMapper.clearDefaultByUserId(userId);
        }

        Address addr = new Address();
        addr.setId(id);
        addr.setReceiver(req.getReceiver());
        addr.setPhone(req.getPhone());
        addr.setProvince(req.getProvince());
        addr.setCity(req.getCity());
        addr.setDistrict(req.getDistrict());
        addr.setDetail(req.getDetail());
        addr.setIsDefault(Boolean.TRUE.equals(req.getIsDefault()) ? 1 : 0);
        addressMapper.update(addr);

        return toVO(addressMapper.findById(id).orElseThrow());
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteAddress(Long userId, Long id) {
        Address addr = findAndValidate(userId, id);
        addressMapper.deleteById(id);
        // 若删除的是默认地址，自动晋升最新的剩余地址为默认
        if (addr.getIsDefault() != null && addr.getIsDefault() == 1) {
            addressMapper.findLatestByUserId(userId)
                    .ifPresent(latest -> addressMapper.setDefaultById(latest.getId()));
        }
        log.info("[Address] deleted id={} userId={}", id, userId);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void setDefaultAddress(Long userId, Long id) {
        findAndValidate(userId, id);
        addressMapper.clearDefaultByUserId(userId);
        addressMapper.setDefaultById(id);
    }

    // ---- helpers ----

    private Address findAndValidate(Long userId, Long id) {
        Address addr = addressMapper.findById(id)
                .orElseThrow(() -> new BusinessException(404, "地址不存在"));
        if (!addr.getUserId().equals(userId)) {
            throw new BusinessException(403, "无权操作此地址");
        }
        return addr;
    }

    private Address buildAddress(Long userId, AddressRequest req) {
        Address addr = new Address();
        addr.setUserId(userId);
        addr.setReceiver(req.getReceiver());
        addr.setPhone(req.getPhone());
        addr.setProvince(req.getProvince());
        addr.setCity(req.getCity());
        addr.setDistrict(req.getDistrict());
        addr.setDetail(req.getDetail());
        return addr;
    }

    private AddressVO toVO(Address a) {
        AddressVO vo = new AddressVO();
        vo.setId(a.getId());
        vo.setReceiver(a.getReceiver());
        vo.setPhone(a.getPhone());
        vo.setProvince(a.getProvince());
        vo.setCity(a.getCity());
        vo.setDistrict(a.getDistrict());
        vo.setDetail(a.getDetail());
        vo.setIsDefault(a.getIsDefault());
        return vo;
    }
}
