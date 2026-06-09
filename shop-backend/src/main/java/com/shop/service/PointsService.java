package com.shop.service;

import com.shop.vo.PageVO;
import com.shop.vo.PointsBalanceVO;
import com.shop.vo.PointsRecordVO;

public interface PointsService {

    PointsBalanceVO getBalance(Long userId);

    PageVO<PointsRecordVO> getRecords(Long userId, int page, int size);

    /** 发放积分（幂等，调用方已确认需发放） */
    void earnPoints(Long userId, int points, String orderId);
}
