package com.shop.service.impl;

import com.shop.common.EsConverter;
import com.shop.entity.Product;
import com.shop.entity.ProductDocument;
import com.shop.entity.SyncFailLog;
import com.shop.mapper.ProductSearchRepository;
import com.shop.mapper.SyncFailLogMapper;
import com.shop.service.ProductSearchService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProductSearchServiceImpl implements ProductSearchService {

    private final ProductSearchRepository searchRepository;
    private final SyncFailLogMapper syncFailLogMapper;

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
