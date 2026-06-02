package com.shop.service.impl;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.shop.common.BusinessException;
import com.shop.common.ErrorCode;
import com.shop.common.RedisKeyConstants;
import com.shop.entity.Product;
import com.shop.mapper.ProductMapper;
import com.shop.service.ProductSearchService;
import com.shop.service.ProductService;
import com.shop.util.CacheUtil;
import com.shop.vo.CategoryBucketVO;
import com.shop.vo.ProductVO;
import com.shop.vo.SearchResultVO;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.redisson.api.RBloomFilter;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProductServiceImpl implements ProductService {

    private static final long PRODUCT_TTL_SECONDS = 1800;
    private static final Set<String> VALID_SORTS = Set.of("", "price_asc", "price_desc", "sales_desc");

    private final ProductMapper productMapper;
    private final ProductSearchService productSearchService;
    private final RedissonClient redissonClient;
    private final RedisTemplate<String, Object> redisTemplate;
    private final CacheUtil cacheUtil;
    private final Cache<Long, ProductVO> localProductCache;

    private RBloomFilter<Long> bloomFilter;

    @PostConstruct
    public void initBloomFilter() {
        try {
            bloomFilter = redissonClient.getBloomFilter(RedisKeyConstants.PRODUCT_BLOOM_FILTER);
            bloomFilter.tryInit(100_000L, 0.01);
            List<Product> all = productMapper.findAll();
            all.forEach(p -> bloomFilter.add(p.getId()));
            log.info("Bloom Filter 初始化完成，加载 {} 个商品 ID", all.size());
        } catch (Exception e) {
            log.warn("Bloom Filter 初始化失败，降级为全量查 DB: {}", e.getMessage());
            bloomFilter = null;
        }
    }

    @Override
    public ProductVO getProduct(Long id) {
        if (bloomFilter != null && !bloomFilter.contains(id)) {
            log.info("Bloom Filter 拦截，商品不存在 id={}", id);
            throw new BusinessException(ErrorCode.PRODUCT_NOT_FOUND);
        }

        ProductVO cached = localProductCache.getIfPresent(id);
        if (cached != null) {
            log.debug("Local cache 命中 id={}", id);
            return cached;
        }

        String redisKey = RedisKeyConstants.productDetailKey(id);
        ProductVO vo = (ProductVO) redisTemplate.opsForValue().get(redisKey);
        if (vo != null) {
            log.debug("Redis cache 命中 id={}", id);
            localProductCache.put(id, vo);
            return vo;
        }

        return rebuildCache(id, redisKey);
    }

    private ProductVO rebuildCache(Long id, String redisKey) {
        RLock lock = redissonClient.getLock(RedisKeyConstants.productLockKey(id));
        try {
            if (lock.tryLock(3, 10, TimeUnit.SECONDS)) {
                try {
                    ProductVO doubleCheck = (ProductVO) redisTemplate.opsForValue().get(redisKey);
                    if (doubleCheck != null) {
                        log.debug("Double-check Redis 命中 id={}", id);
                        localProductCache.put(id, doubleCheck);
                        return doubleCheck;
                    }

                    log.info("DB 查询商品 id={}", id);
                    Product product = productMapper.findById(id)
                            .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
                    ProductVO vo = toVO(product);

                    cacheUtil.setWithRandomTTL(redisKey, vo, PRODUCT_TTL_SECONDS, TimeUnit.SECONDS);
                    localProductCache.put(id, vo);
                    return vo;
                } finally {
                    if (lock.isHeldByCurrentThread()) lock.unlock();
                }
            } else {
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

    @Override
    public SearchResultVO listProducts(int page, int size, String keyword,
                                       String category, BigDecimal minPrice, BigDecimal maxPrice,
                                       String sort, String source) {
        // Validate
        if (keyword != null && keyword.length() > 50) {
            throw new BusinessException(400, "关键词过长，请控制在50字以内");
        }
        String effectiveSort = sort != null ? sort : "";
        if (!VALID_SORTS.contains(effectiveSort)) {
            throw new BusinessException(400, "无效的排序参数，可选：price_asc / price_desc / sales_desc");
        }
        if (minPrice != null && minPrice.compareTo(BigDecimal.ZERO) < 0) {
            throw new BusinessException(400, "最低价不能为负数");
        }
        if (maxPrice != null && maxPrice.compareTo(BigDecimal.ZERO) < 0) {
            throw new BusinessException(400, "最高价不能为负数");
        }
        if (minPrice != null && maxPrice != null && minPrice.compareTo(maxPrice) > 0) {
            throw new BusinessException(400, "最低价不能大于最高价");
        }

        // Route to ES when any ES-specific param is present
        boolean useEs = (keyword != null && !keyword.isBlank())
                || (category != null && !category.isBlank())
                || minPrice != null
                || maxPrice != null
                || !effectiveSort.isBlank();

        if (useEs && !"mysql".equals(source)) {
            try {
                return productSearchService.search(keyword, category, minPrice, maxPrice,
                        effectiveSort, page, size);
            } catch (Exception e) {
                log.warn("[ES] search failed, fallback to MySQL: {}", e.getMessage());
            }
        }
        return listProductsByMysql(page, size, keyword);
    }

    private SearchResultVO listProductsByMysql(int page, int size, String keyword) {
        PageHelper.startPage(page, size);
        List<Product> list = productMapper.findByKeyword(keyword);
        PageInfo<Product> pageInfo = new PageInfo<>(list);

        SearchResultVO result = new SearchResultVO();
        result.setProducts(list.stream().map(this::toVO).collect(Collectors.toList()));
        result.setTotal(pageInfo.getTotal());
        result.setCategoryBuckets(Collections.emptyList());
        return result;
    }

    public void onProductCreated(Long productId) {
        if (bloomFilter != null) bloomFilter.add(productId);
    }

    public void evictProductCache(Long productId) {
        localProductCache.invalidate(productId);
        redisTemplate.delete(RedisKeyConstants.productDetailKey(productId));
        log.info("商品缓存已清除 id={}", productId);
    }

    @Override
    public ProductVO createProduct(Product product) {
        productMapper.insert(product);
        productSearchService.syncSave(product);
        return toVO(product);
    }

    @Override
    public ProductVO updateProduct(Long id, Product product) {
        productMapper.findById(id)
                .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
        product.setId(id);
        productMapper.update(product);
        Product updated = productMapper.findById(id).orElse(product);
        productSearchService.syncSave(updated);
        return toVO(updated);
    }

    @Override
    public void deleteProduct(Long id) {
        productMapper.findById(id)
                .orElseThrow(() -> new BusinessException(ErrorCode.PRODUCT_NOT_FOUND));
        productMapper.deleteById(id);
        productSearchService.syncDelete(id);
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
