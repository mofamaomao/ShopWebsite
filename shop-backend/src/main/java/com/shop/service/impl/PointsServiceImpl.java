package com.shop.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.entity.PointsRecord;
import com.shop.mapper.PointsRecordMapper;
import com.shop.mapper.UserMapper;
import com.shop.service.PointsService;
import com.shop.vo.PageVO;
import com.shop.vo.PointsBalanceVO;
import com.shop.vo.PointsRecordVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class PointsServiceImpl implements PointsService {

    private final UserMapper userMapper;
    private final PointsRecordMapper pointsRecordMapper;

    @Value("${points.redeem-rate:100}")
    private int redeemRate;

    @Value("${points.max-redeem-pct:0.2}")
    private double maxRedeemPct;

    @Override
    public PointsBalanceVO getBalance(Long userId) {
        PointsBalanceVO vo = new PointsBalanceVO();
        vo.setBalance(userMapper.getPoints(userId));
        vo.setTotalEarned(pointsRecordMapper.sumEarned(userId));
        vo.setTotalUsed(pointsRecordMapper.sumUsed(userId));
        vo.setRedeemRate(redeemRate);
        vo.setMaxRedeemPct(maxRedeemPct);
        return vo;
    }

    @Override
    public PageVO<PointsRecordVO> getRecords(Long userId, int page, int size) {
        PageHelper.startPage(page, size);
        List<PointsRecord> list = pointsRecordMapper.findByUserId(userId);
        PageInfo<PointsRecord> info = new PageInfo<>(list);
        PageVO<PointsRecordVO> vo = new PageVO<>();
        vo.setList(info.getList().stream().map(this::toVO).collect(Collectors.toList()));
        vo.setTotal(info.getTotal());
        vo.setPage(page);
        vo.setSize(size);
        return vo;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void earnPoints(Long userId, int points, String orderId) {
        userMapper.addPoints(userId, points);
        int balance = userMapper.getPoints(userId);
        PointsRecord record = new PointsRecord();
        record.setUserId(userId);
        record.setType(1);
        record.setPoints(points);
        record.setBalance(balance);
        record.setSource("订单支付");
        record.setOrderId(orderId);
        record.setCreatedAt(LocalDateTime.now());
        pointsRecordMapper.insert(record);
        log.info("[Points] earned userId={} points={} balance={} orderId={}", userId, points, balance, orderId);
    }

    private PointsRecordVO toVO(PointsRecord r) {
        PointsRecordVO vo = new PointsRecordVO();
        vo.setId(r.getId());
        vo.setType(r.getType());
        vo.setPoints(r.getPoints());
        vo.setBalance(r.getBalance());
        vo.setSource(r.getSource());
        vo.setOrderId(r.getOrderId());
        vo.setCreatedAt(r.getCreatedAt());
        return vo;
    }
}
