package com.shop.service.impl;

import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import co.elastic.clients.elasticsearch._types.query_dsl.TextQueryType;
import com.shop.common.EsConverter;
import com.shop.entity.Product;
import com.shop.entity.ProductDocument;
import com.shop.entity.SyncFailLog;
import com.shop.mapper.SyncFailLogMapper;
import com.shop.repository.ProductSearchRepository;
import com.shop.service.ProductSearchService;
import com.shop.vo.PageVO;
import com.shop.vo.ProductVO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.elasticsearch.core.ElasticsearchOperations;
import org.springframework.data.elasticsearch.core.SearchHit;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.data.elasticsearch.client.elc.NativeQuery;
import org.springframework.data.elasticsearch.core.query.HighlightQuery;
import org.springframework.data.elasticsearch.core.query.highlight.Highlight;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightField;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightFieldParameters;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
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
    public PageVO<ProductVO> search(String keyword, int page, int size) {
        Query esQuery = Query.of(q -> q
                .multiMatch(mm -> mm
                        .query(keyword)
                        .fields(List.of("name^2", "description"))
                        .type(TextQueryType.BestFields)));

        HighlightFieldParameters hlParams = HighlightFieldParameters.builder()
                .withPreTags("<em class='search-hl'>")
                .withPostTags("</em>")
                .build();
        HighlightQuery hlQuery = new HighlightQuery(
                new Highlight(List.of(new HighlightField("name", hlParams))),
                ProductDocument.class);

        NativeQuery nativeQuery = NativeQuery.builder()
                .withQuery(esQuery)
                .withHighlightQuery(hlQuery)
                .withPageable(PageRequest.of(page - 1, size))
                .build();

        SearchHits<ProductDocument> hits = elasticsearchOperations.search(nativeQuery, ProductDocument.class);

        List<ProductVO> vos = new ArrayList<>();
        for (SearchHit<ProductDocument> hit : hits) {
            ProductVO vo = EsConverter.toVO(hit.getContent());
            List<String> hl = hit.getHighlightField("name");
            if (!hl.isEmpty()) {
                vo.setHighlightName(hl.get(0));
            }
            vos.add(vo);
        }

        PageVO<ProductVO> result = new PageVO<>();
        result.setList(vos);
        result.setTotal(hits.getTotalHits());
        result.setPage(page);
        result.setSize(size);
        return result;
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
