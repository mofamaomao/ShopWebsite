package com.shop.common;

import com.shop.entity.Product;
import com.shop.entity.ProductDocument;

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
}
