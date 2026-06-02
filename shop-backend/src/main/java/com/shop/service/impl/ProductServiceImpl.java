package com.shop.service.impl;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.service.ProductService;
import com.shop.util.CacheUtil;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.RBloomFilter;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProductServiceImpl implements ProductService {

    private static final long PRODUCT_TTL_SECONDS = 1800; // 30 min base TTL

    private final ProductMapper productMapper;
    private final RedissonClient redissonClient;
    private final RedisTemplate<String, Object> redisTemplate;
    private final CacheUtil cacheUtil;
    private final Cache<Long, ProductVO> localProductCache;

    private RBloomFilter<Long> bloomFilter;

    // ── 防线一：布隆过滤器初始化 ──────────────────────────────────────────────
    @PostConstruct
    public void initBloomFilter() {
        try {
            bloomFilter = redissonClient.getBloomFilter(RedisKeyConstants.PRODUCT_BLOOM_FILTER);
            bloomFilter.tryInit(100_000L, 0.01);
            List<Product> all = productMapper.findAll();
            all.forEach(p -> bloomFilter.add(p.getId()));
            log.info("Bloom Filter 初始化完成，加载 {} 个商品 ID", all.size());
        } catch (Exception e) {
            // 初始化失败降级：bloomFilter 置 null，后续跳过过滤直接查 DB
            log.warn("Bloom Filter 初始化失败，降级为全量查 DB: {}", e.getMessage());
            bloomFilter = null;
        }
    }

    // ── 三级缓存查询主流程 ────────────────────────────────────────────────────
    @Override
    public ProductVO getProduct(Long id) {
        // 防线一：布隆过滤器拦截不存在的 ID，防止缓存穿透
        if (bloomFilter != null && !bloomFilter.contains(id)) {
            log.info("Bloom Filter 拦截，商品不存在 id={}", id);
            throw new BusinessException(ErrorCode.PRODUCT_NOT_FOUND);
        }

        // 第一级：本地 Caffeine 缓存（热点数据，5s TTL）
        ProductVO cached = localProductCache.getIfPresent(id);
        if (cached != null) {
            log.debug("Local cache 命中 id={}", id);
            return cached;
        }

        // 第二级：Redis 缓存
        String redisKey = RedisKeyConstants.productDetailKey(id);
        ProductVO vo = (ProductVO) redisTemplate.opsForValue().get(redisKey);
        if (vo != null) {
            log.debug("Redis cache 命中 id={}", id);
            localProductCache.put(id, vo);
            return vo;
        }

        // 防线二：分布式互斥锁防缓存击穿，只允许一个线程重建缓存
        return rebuildCache(id, redisKey);
    }

    private ProductVO rebuildCache(Long id, String redisKey) {
        RLock lock = redissonClient.getLock(RedisKeyConstants.productLockKey(id));
        try {
            if (lock.tryLock(3, 10, TimeUnit.SECONDS)) {
                try {
                    // Double-check：拿到锁后再查一次 Redis，防止重复重建
                    ProductVO doubleCheck = (ProductVO) redisTemplate.opsForValue().get(redisKey);
                    if (doubleCheck != null) {
                        log.debug("Double-check Redis 命中 id={}", id);
                        localProductCache.put(id, doubleCheck);
                        return doubleCheck;
                    }

                    // 第三级：查 DB
                    log.info("DB 查询商品 id={}", id);
                    Product product = productMapper.findById(id)
                            .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
                    ProductVO vo = toVO(product);

                    // 防线三：随机 TTL 防缓存雪崩
                    cacheUtil.setWithRandomTTL(redisKey, vo, PRODUCT_TTL_SECONDS, TimeUnit.SECONDS);
                    localProductCache.put(id, vo);
                    return vo;
                } finally {
                    if (lock.isHeldByCurrentThread()) lock.unlock();
                }
            } else {
                // 未拿到锁：降级，短暂等待后再读一次 Redis（大概率已被其他线程重建）
                log.warn("未获取到重建锁，降级等待重试 id={}", id);
                Thread.sleep(200);
                ProductVO fallback = (ProductVO) redisTemplate.opsForValue().get(redisKey);
                if (fallback != null) return fallback;
                throw new BusinessException(ErrorCode.SYSTEM_BUSY);
            }
        } catch (BusinessException e) {
            throw e;
        } catch (Exception e) {
            log.error("缓存重建异常 id={}", id, e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR);
        }
    }

    // ── 商品列表（不走缓存，分页直查 DB）────────────────────────────────────
    @Override
    public PageVO<ProductVO> listProducts(int page, int size, String keyword) {
        PageHelper.startPage(page, size);
        List<Product> list = productMapper.findByKeyword(keyword);
        PageInfo<Product> pageInfo = new PageInfo<>(list);

        PageVO<ProductVO> pageVO = new PageVO<>();
        pageVO.setList(list.stream().map(this::toVO).collect(Collectors.toList()));
        pageVO.setTotal(pageInfo.getTotal());
        pageVO.setPage(page);
        pageVO.setSize(size);
        return pageVO;
    }

    // ── 商品新增时同步布隆过滤器（Cache-Aside delete 策略）───────────────────
    public void onProductCreated(Long productId) {
        if (bloomFilter != null) {
            bloomFilter.add(productId);
        }
        // 新增不需要删缓存，尚无缓存
    }

    // ── 商品更新时先改 DB，再删缓存（Cache-Aside）───────────────────────────
    public void evictProductCache(Long productId) {
        localProductCache.invalidate(productId);
        redisTemplate.delete(RedisKeyConstants.productDetailKey(productId));
        log.info("商品缓存已清除 id={}", productId);
    }

    private ProductVO toVO(Product p) {
        ProductVO vo = new ProductVO();
        vo.setId(p.getId());
        vo.setName(p.getName());
        vo.setPrice(p.getPrice());
        vo.setStock(p.getStock());
        vo.setCategory(p.getCategory());
        vo.setImageUrl(p.getImageUrl());
        vo.setDescription(p.getDescription());
        return vo;
    }
}
