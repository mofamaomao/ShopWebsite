package com.shop.service.impl;

import com.github.benmanes.caffeine.cache.Cache;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.util.CacheUtil;
import com.shop.vo.ProductVO;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.redisson.api.RBloomFilter;
import org.redisson.api.RedissonClient;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNoException;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 验收项：布隆过滤器初始化 — 正常路径 & 降级路径
 */
@ExtendWith(MockitoExtension.class)
class BloomFilterInitTest {

    @Mock private ProductMapper productMapper;
    @Mock private RedissonClient redissonClient;
    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private CacheUtil cacheUtil;
    @Mock private Cache<Long, ProductVO> localProductCache;
    @Mock private RBloomFilter<Long> bloomFilter;

    @InjectMocks
    private ProductServiceImpl service;

    @Test
    @DisplayName("初始化：全量 productId 成功加载到布隆过滤器")
    void initBloomFilter_loadsAllProductIds() {
        doReturn(bloomFilter).when(redissonClient).getBloomFilter(anyString());
        when(bloomFilter.tryInit(anyLong(), anyDouble())).thenReturn(true);

        Product p1 = product(1L);
        Product p2 = product(2L);
        when(productMapper.findAll()).thenReturn(List.of(p1, p2));

        service.initBloomFilter();

        verify(bloomFilter).tryInit(100_000L, 0.01);
        verify(bloomFilter).add(1L);
        verify(bloomFilter).add(2L);
        assertThat(ReflectionTestUtils.getField(service, "bloomFilter")).isNotNull();
    }

    @Test
    @DisplayName("初始化：Redisson 异常时降级，bloomFilter 置 null，服务正常启动")
    void initBloomFilter_redissonThrows_degradesGracefully() {
        when(redissonClient.getBloomFilter(anyString()))
                .thenThrow(new RuntimeException("Redis 连接失败"));

        assertThatNoException().isThrownBy(() -> service.initBloomFilter());

        // 降级后 bloomFilter 为 null
        assertThat(ReflectionTestUtils.getField(service, "bloomFilter")).isNull();
        verifyNoInteractions(productMapper);
    }

    @Test
    @DisplayName("初始化：DB 查询异常时降级，bloomFilter 置 null")
    void initBloomFilter_dbThrows_degradesGracefully() {
        doReturn(bloomFilter).when(redissonClient).getBloomFilter(anyString());
        when(bloomFilter.tryInit(anyLong(), anyDouble())).thenReturn(true);
        when(productMapper.findAll()).thenThrow(new RuntimeException("DB 不可用"));

        assertThatNoException().isThrownBy(() -> service.initBloomFilter());

        assertThat(ReflectionTestUtils.getField(service, "bloomFilter")).isNull();
    }

    private Product product(Long id) {
        Product p = new Product();
        p.setId(id);
        return p;
    }
}
