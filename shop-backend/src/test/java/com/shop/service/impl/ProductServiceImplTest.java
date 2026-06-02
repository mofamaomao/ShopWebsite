package com.shop.service.impl;

import com.github.benmanes.caffeine.cache.Cache;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.util.CacheUtil;
import com.shop.vo.ProductVO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.redisson.api.RBloomFilter;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 验收项：缓存穿透（布隆过滤器）、缓存击穿（分布式锁 + double-check）、
 *         Cache-Aside 读写流程、缓存一致性（主动删除）
 */
@ExtendWith(MockitoExtension.class)
class ProductServiceImplTest {

    @Mock private ProductMapper productMapper;
    @Mock private RedissonClient redissonClient;
    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private CacheUtil cacheUtil;
    @Mock private Cache<Long, ProductVO> localProductCache;
    @Mock private RBloomFilter<Long> bloomFilter;
    @Mock private RLock lock;
    @Mock private ValueOperations<String, Object> valueOps;

    @InjectMocks
    private ProductServiceImpl service;

    @BeforeEach
    void setUp() {
        // 注入 bloomFilter（@PostConstruct 不在单元测试中执行，手动注入）
        ReflectionTestUtils.setField(service, "bloomFilter", bloomFilter);
        // lenient：部分测试提前 return（如布隆拦截），不会调用 opsForValue()
        lenient().when(redisTemplate.opsForValue()).thenReturn(valueOps);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 防线一：缓存穿透 — 布隆过滤器
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("穿透防护：ID 不在布隆过滤器中 → 直接抛 404，不查 DB 不查 Redis")
    void getProduct_bloomFilterMiss_throwsNotFound() {
        when(bloomFilter.contains(99999L)).thenReturn(false);

        assertThatThrownBy(() -> service.getProduct(99999L))
                .isInstanceOf(BusinessException.class)
                .extracting(e -> ((BusinessException) e).getCode())
                .isEqualTo(ErrorCode.PRODUCT_NOT_FOUND.getCode());

        verifyNoInteractions(productMapper);
        verify(valueOps, never()).get(anyString());
    }

    @Test
    @DisplayName("穿透防护：布隆过滤器为 null（降级模式）→ 走正常查询流程")
    void getProduct_bloomFilterNull_fallsThrough() throws Exception {
        ReflectionTestUtils.setField(service, "bloomFilter", null);

        // Local miss、Redis miss、DB 有数据
        when(localProductCache.getIfPresent(1L)).thenReturn(null);
        when(valueOps.get(anyString())).thenReturn(null);
        when(redissonClient.getLock(anyString())).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(true);
        when(lock.isHeldByCurrentThread()).thenReturn(true);
        when(productMapper.findById(1L)).thenReturn(Optional.of(buildProduct(1L)));

        ProductVO result = service.getProduct(1L);
        assertThat(result.getId()).isEqualTo(1L);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cache-Aside 读流程
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("Cache-Aside：本地缓存命中 → 不查 Redis 不查 DB")
    void getProduct_localCacheHit_skipsRedisAndDb() {
        when(bloomFilter.contains(1L)).thenReturn(true);
        ProductVO cached = buildVO(1L);
        when(localProductCache.getIfPresent(1L)).thenReturn(cached);

        ProductVO result = service.getProduct(1L);

        assertThat(result).isSameAs(cached);
        verify(valueOps, never()).get(anyString());
        verifyNoInteractions(productMapper);
    }

    @Test
    @DisplayName("Cache-Aside：Redis 命中 → 不查 DB，写入本地缓存")
    void getProduct_redisCacheHit_skipsDb() {
        when(bloomFilter.contains(2L)).thenReturn(true);
        when(localProductCache.getIfPresent(2L)).thenReturn(null);
        ProductVO redisVO = buildVO(2L);
        when(valueOps.get("product:detail:2")).thenReturn(redisVO);

        ProductVO result = service.getProduct(2L);

        assertThat(result.getId()).isEqualTo(2L);
        verifyNoInteractions(productMapper);
        verify(localProductCache).put(2L, redisVO);
    }

    @Test
    @DisplayName("Cache-Aside：全部 miss → 查 DB，写 Redis（随机 TTL），写本地缓存")
    void getProduct_allMiss_queriesDbAndPopulatesCache() throws Exception {
        when(bloomFilter.contains(3L)).thenReturn(true);
        when(localProductCache.getIfPresent(3L)).thenReturn(null);
        when(valueOps.get(anyString())).thenReturn(null);
        when(redissonClient.getLock(anyString())).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(true);
        when(lock.isHeldByCurrentThread()).thenReturn(true);
        when(productMapper.findById(3L)).thenReturn(Optional.of(buildProduct(3L)));

        ProductVO result = service.getProduct(3L);

        assertThat(result.getId()).isEqualTo(3L);
        // 验证写缓存走的是随机 TTL 方法
        verify(cacheUtil).setWithRandomTTL(eq("product:detail:3"), any(), anyLong(), any());
        verify(localProductCache).put(eq(3L), any());
    }

    @Test
    @DisplayName("Cache-Aside：DB 无数据 → 抛 404")
    void getProduct_dbMiss_throwsNotFound() throws Exception {
        when(bloomFilter.contains(5L)).thenReturn(true);
        when(localProductCache.getIfPresent(5L)).thenReturn(null);
        when(valueOps.get(anyString())).thenReturn(null);
        when(redissonClient.getLock(anyString())).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(true);
        when(lock.isHeldByCurrentThread()).thenReturn(true);
        when(productMapper.findById(5L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getProduct(5L))
                .isInstanceOf(BusinessException.class)
                .extracting(e -> ((BusinessException) e).getCode())
                .isEqualTo(ErrorCode.PRODUCT_NOT_FOUND.getCode());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 防线二：缓存击穿 — 分布式锁 + double-check
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("击穿防护：拿到锁后 double-check Redis 命中 → 不查 DB")
    void getProduct_lockAcquired_doubleCheckHits_skipsDb() throws Exception {
        when(bloomFilter.contains(4L)).thenReturn(true);
        when(localProductCache.getIfPresent(4L)).thenReturn(null);
        // 第一次 Redis miss（触发锁），第二次 Redis hit（double-check）
        ProductVO afterRebuild = buildVO(4L);
        when(valueOps.get("product:detail:4"))
                .thenReturn(null)
                .thenReturn(afterRebuild);
        when(redissonClient.getLock("lock:product:4")).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(true);
        when(lock.isHeldByCurrentThread()).thenReturn(true);

        ProductVO result = service.getProduct(4L);

        assertThat(result.getId()).isEqualTo(4L);
        // double-check 命中，DB 不应被调用
        verifyNoInteractions(productMapper);
    }

    @Test
    @DisplayName("击穿防护：未拿到锁 → 等待后从 Redis 降级读取")
    void getProduct_lockNotAcquired_fallbackToRedis() throws Exception {
        when(bloomFilter.contains(6L)).thenReturn(true);
        when(localProductCache.getIfPresent(6L)).thenReturn(null);
        // 第一次 miss 触发锁，未拿到锁后等待，等待后 Redis 有值
        ProductVO stale = buildVO(6L);
        when(valueOps.get("product:detail:6"))
                .thenReturn(null)   // 首次 Redis miss
                .thenReturn(stale); // 等待后 Redis 已被其他线程重建
        when(redissonClient.getLock(anyString())).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(false);

        ProductVO result = service.getProduct(6L);

        assertThat(result.getId()).isEqualTo(6L);
        verifyNoInteractions(productMapper);
    }

    @Test
    @DisplayName("击穿防护：未拿到锁且降级 Redis 也 miss → 抛 SYSTEM_BUSY")
    void getProduct_lockNotAcquired_redisMissAfterWait_throwsBusy() throws Exception {
        when(bloomFilter.contains(7L)).thenReturn(true);
        when(localProductCache.getIfPresent(7L)).thenReturn(null);
        when(valueOps.get(anyString())).thenReturn(null); // 两次都 miss
        when(redissonClient.getLock(anyString())).thenReturn(lock);
        when(lock.tryLock(anyLong(), anyLong(), any())).thenReturn(false);

        assertThatThrownBy(() -> service.getProduct(7L))
                .isInstanceOf(BusinessException.class)
                .extracting(e -> ((BusinessException) e).getCode())
                .isEqualTo(ErrorCode.SYSTEM_BUSY.getCode());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 缓存一致性 — Cache-Aside delete 策略
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("缓存一致性：evictProductCache() 同时清除本地缓存和 Redis key")
    void evictProductCache_invalidatesBothCaches() {
        service.evictProductCache(1L);

        verify(localProductCache).invalidate(1L);
        verify(redisTemplate).delete("product:detail:1");
    }

    @Test
    @DisplayName("缓存一致性：新增商品时布隆过滤器同步添加 ID")
    void onProductCreated_addsToBloomFilter() {
        service.onProductCreated(10L);
        verify(bloomFilter).add(10L);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────────

    private Product buildProduct(Long id) {
        Product p = new Product();
        p.setId(id);
        p.setName("商品" + id);
        p.setPrice(BigDecimal.valueOf(99.9));
        p.setStock(100);
        p.setCategory("test");
        return p;
    }

    private ProductVO buildVO(Long id) {
        ProductVO vo = new ProductVO();
        vo.setId(id);
        vo.setName("商品" + id);
        vo.setPrice(BigDecimal.valueOf(99.9));
        return vo;
    }
}
