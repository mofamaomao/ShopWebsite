package com.shop.common;

import com.shop.entity.Product;
import com.shop.entity.ProductDocument;
import com.shop.vo.ProductVO;

import java.math.BigDecimal;

public final class EsConverter {

    private EsConverter() {}

    public static ProductDocument toDocument(Product p) {
        ProductDocument doc = new ProductDocument();
        doc.setId(p.getId());
        doc.setName(p.getName());
        doc.setDescription(p.getDescription());
        doc.setCategory(p.getCategory());
        doc.setPrice(p.getPrice() != null ? p.getPrice().doubleValue() : null);
        doc.setStock(p.getStock());
        doc.setSales(0);
        doc.setImageUrl(p.getImageUrl());
        doc.setCreatedAt(System.currentTimeMillis());
        return doc;
    }

    public static ProductVO toVO(ProductDocument doc) {
        ProductVO vo = new ProductVO();
        vo.setId(doc.getId());
        vo.setName(doc.getName());
        vo.setDescription(doc.getDescription());
        vo.setCategory(doc.getCategory());
        vo.setPrice(doc.getPrice() != null ? BigDecimal.valueOf(doc.getPrice()) : null);
        vo.setStock(doc.getStock());
        vo.setImageUrl(doc.getImageUrl());
        return vo;
    }
}
