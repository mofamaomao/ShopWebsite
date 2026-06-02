package com.shop.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.RepeatedTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 验收项：缓存雪崩防护 — 随机 TTL
 */
@ExtendWith(MockitoExtension.class)
class CacheUtilTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private ValueOperations<String, Object> valueOps;

    @InjectMocks
    private CacheUtil cacheUtil;

    @Test
    @DisplayName("雪崩防护：TTL 必须在 [baseTTL, baseTTL+300) 区间内")
    void setWithRandomTTL_ttlInExpectedRange() {
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        ArgumentCaptor<Long> ttlCaptor = ArgumentCaptor.forClass(Long.class);

        cacheUtil.setWithRandomTTL("key:1", "value", 1800L, TimeUnit.SECONDS);

        verify(valueOps).set(eq("key:1"), eq("value"), ttlCaptor.capture(), eq(TimeUnit.SECONDS));
        long actualTTL = ttlCaptor.getValue();
        assertThat(actualTTL)
                .as("TTL 应在 [1800, 2100) 之间")
                .isGreaterThanOrEqualTo(1800L)
                .isLessThan(2100L);
    }

    @Test
    @DisplayName("雪崩防护：同 baseTTL 多次写入，TTL 值不应全部相同（验证随机性）")
    void setWithRandomTTL_multipleCalls_produceDifferentTTLs() {
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        ArgumentCaptor<Long> ttlCaptor = ArgumentCaptor.forClass(Long.class);

        // 写入 20 次，至少应出现 2 个不同的 TTL 值
        for (int i = 0; i < 20; i++) {
            cacheUtil.setWithRandomTTL("key:" + i, "v", 1800L, TimeUnit.SECONDS);
        }

        verify(valueOps, times(20)).set(anyString(), anyString(), ttlCaptor.capture(), any());
        Set<Long> distinctTTLs = new HashSet<>(ttlCaptor.getAllValues());
        assertThat(distinctTTLs.size())
                .as("20 次写入应出现多个不同 TTL，验证随机抖动有效")
                .isGreaterThan(1);
    }

    @Test
    @DisplayName("雪崩防护：TTL 单位正确传递（SECONDS）")
    void setWithRandomTTL_usesCorrectTimeUnit() {
        when(redisTemplate.opsForValue()).thenReturn(valueOps);

        cacheUtil.setWithRandomTTL("key:unit", "v", 1800L, TimeUnit.SECONDS);

        verify(valueOps).set(anyString(), anyString(), anyLong(), eq(TimeUnit.SECONDS));
    }

    @RepeatedTest(5)
    @DisplayName("雪崩防护：每次调用 TTL 均落在合法区间（重复5次确认）")
    void setWithRandomTTL_repeatedCallsAllInRange() {
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        ArgumentCaptor<Long> cap = ArgumentCaptor.forClass(Long.class);

        cacheUtil.setWithRandomTTL("k", "v", 600L, TimeUnit.SECONDS);

        verify(valueOps).set(anyString(), any(), cap.capture(), any());
        assertThat(cap.getValue()).isBetween(600L, 899L);
        reset(valueOps);
    }
}
