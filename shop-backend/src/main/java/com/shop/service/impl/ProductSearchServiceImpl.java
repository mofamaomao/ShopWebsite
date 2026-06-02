package com.shop.service.impl;

import co.elastic.clients.elasticsearch._types.SortOptions;
import co.elastic.clients.elasticsearch._types.SortOrder;
import co.elastic.clients.elasticsearch._types.aggregations.Aggregation;
import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import co.elastic.clients.elasticsearch._types.query_dsl.TextQueryType;
import co.elastic.clients.json.JsonData;
import com.shop.common.EsConverter;
import com.shop.entity.Product;
import com.shop.entity.ProductDocument;
import com.shop.entity.SyncFailLog;
import com.shop.mapper.SyncFailLogMapper;
import com.shop.repository.ProductSearchRepository;
import com.shop.service.ProductSearchService;
import com.shop.vo.CategoryBucketVO;
import com.shop.vo.ProductVO;
import com.shop.vo.SearchResultVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.elasticsearch.client.elc.ElasticsearchAggregation;
import org.springframework.data.elasticsearch.client.elc.ElasticsearchAggregations;
import org.springframework.data.elasticsearch.client.elc.NativeQuery;
import org.springframework.data.elasticsearch.core.ElasticsearchOperations;
import org.springframework.data.elasticsearch.core.SearchHit;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.data.elasticsearch.core.query.HighlightQuery;
import org.springframework.data.elasticsearch.core.query.highlight.Highlight;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightField;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightFieldParameters;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProductSearchServiceImpl implements ProductSearchService {

    private final ProductSearchRepository searchRepository;
    private final SyncFailLogMapper syncFailLogMapper;
    private final ElasticsearchOperations elasticsearchOperations;

    @Override
    public int bulkInit(List<Product> products) {
        List<ProductDocument> docs = products.stream()
                .map(EsConverter::toDocument)
                .collect(Collectors.toList());
        searchRepository.saveAll(docs);
        return docs.size();
    }

    @Override
    public void syncSave(Product product) {
        try {
            searchRepository.save(EsConverter.toDocument(product));
        } catch (Exception e) {
            log.error("[ES] syncSave failed for productId={}: {}", product.getId(), e.getMessage());
            writeFailLog(product.getId(), "SAVE", e.getMessage());
        }
    }

    @Override
    public void syncDelete(Long productId) {
        try {
            searchRepository.deleteById(productId);
        } catch (Exception e) {
            log.error("[ES] syncDelete failed for productId={}: {}", productId, e.getMessage());
            writeFailLog(productId, "DELETE", e.getMessage());
        }
    }

    @Override
    public SearchResultVO search(String keyword, String category,
                                 BigDecimal minPrice, BigDecimal maxPrice,
                                 String sort, int page, int size) {
        // 1. Build bool query
        List<Query> mustClauses = new ArrayList<>();
        List<Query> filterClauses = new ArrayList<>();

        if (keyword != null && !keyword.isBlank()) {
            mustClauses.add(Query.of(q -> q.multiMatch(mm -> mm
                    .query(keyword)
                    .fields(List.of("name^2", "description"))
                    .type(TextQueryType.BestFields))));
        } else {
            mustClauses.add(Query.of(q -> q.matchAll(ma -> ma)));
        }

        if (category != null && !category.isBlank()) {
            filterClauses.add(Query.of(q -> q.term(t -> t.field("category").value(category))));
        }

        if (minPrice != null || maxPrice != null) {
            final Double minVal = minPrice != null ? minPrice.doubleValue() : null;
            final Double maxVal = maxPrice != null ? maxPrice.doubleValue() : null;
            filterClauses.add(buildPriceRangeFilter(minVal, maxVal));
        }

        Query finalQuery = Query.of(q -> q.bool(b -> b.must(mustClauses).filter(filterClauses)));

        // 2. Highlight (only when keyword present)
        HighlightQuery hlQuery = null;
        if (keyword != null && !keyword.isBlank()) {
            HighlightFieldParameters hlParams = HighlightFieldParameters.builder()
                    .withPreTags("<em class='search-hl'>")
                    .withPostTags("</em>")
                    .build();
            hlQuery = new HighlightQuery(
                    new Highlight(List.of(new HighlightField("name", hlParams))),
                    ProductDocument.class);
        }

        // 3. Build NativeQuery with aggregation + optional sort
        var queryBuilder = NativeQuery.builder()
                .withQuery(finalQuery)
                .withAggregation("category_count",
                        Aggregation.of(a -> a.terms(t -> t.field("category").size(20))))
                .withPageable(PageRequest.of(page - 1, size));

        if (hlQuery != null) {
            queryBuilder.withHighlightQuery(hlQuery);
        }

        for (SortOptions so : buildSortOptions(sort)) {
            queryBuilder.withSort(so);
        }

        // 4. Execute search
        SearchHits<ProductDocument> hits = elasticsearchOperations.search(
                queryBuilder.build(), ProductDocument.class);

        // 5. Map hits to VOs with highlight
        List<ProductVO> vos = new ArrayList<>();
        for (SearchHit<ProductDocument> hit : hits) {
            ProductVO vo = EsConverter.toVO(hit.getContent());
            List<String> hl = hit.getHighlightField("name");
            if (!hl.isEmpty()) vo.setHighlightName(hl.get(0));
            vos.add(vo);
        }

        // 6. Parse category aggregation
        List<CategoryBucketVO> buckets = new ArrayList<>();
        if (hits.getAggregations() != null) {
            ElasticsearchAggregations aggs = (ElasticsearchAggregations) hits.getAggregations();
            ElasticsearchAggregation catAgg = aggs.get("category_count");
            if (catAgg != null) {
                // .aggregation() → Spring wrapper; .getAggregate() → co.elastic.clients Aggregate
                catAgg.aggregation().getAggregate().sterms().buckets().array().forEach(b -> {
                    CategoryBucketVO vo = new CategoryBucketVO();
                    vo.setCategory(b.key().stringValue());
                    vo.setCount(b.docCount());
                    buckets.add(vo);
                });
            }
        }

        SearchResultVO result = new SearchResultVO();
        result.setProducts(vos);
        result.setTotal(hits.getTotalHits());
        result.setCategoryBuckets(buckets);
        return result;
    }

    private Query buildPriceRangeFilter(Double minVal, Double maxVal) {
        return Query.of(q -> q.range(r -> {
            r.field("price");
            if (minVal != null) r.gte(JsonData.of(minVal));
            if (maxVal != null) r.lte(JsonData.of(maxVal));
            return r;
        }));
    }

    private List<SortOptions> buildSortOptions(String sort) {
        if (sort == null || sort.isBlank()) return Collections.emptyList();
        return switch (sort) {
            case "price_asc" -> List.of(
                    SortOptions.of(s -> s.field(f -> f.field("price").order(SortOrder.Asc))));
            case "price_desc" -> List.of(
                    SortOptions.of(s -> s.field(f -> f.field("price").order(SortOrder.Desc))));
            case "sales_desc" -> List.of(
                    SortOptions.of(s -> s.field(f -> f.field("sales").order(SortOrder.Desc))));
            default -> Collections.emptyList();
        };
    }

    private void writeFailLog(Long productId, String operation, String errorMsg) {
        try {
            SyncFailLog record = new SyncFailLog();
            record.setProductId(productId);
            record.setOperation(operation);
            record.setErrorMsg(errorMsg != null && errorMsg.length() > 500
                    ? errorMsg.substring(0, 500) : errorMsg);
            record.setCreatedAt(LocalDateTime.now());
            syncFailLogMapper.insert(record);
        } catch (Exception ex) {
            log.error("[ES] writeFailLog itself failed: {}", ex.getMessage());
        }
    }
}
