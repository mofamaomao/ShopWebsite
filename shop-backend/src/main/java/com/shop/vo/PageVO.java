package com.shop.vo;

import lombok.Data;
import java.util.List;

@Data
public class PageVO<T> {
    private List<T> list;
    private long total;
    private int page;
    private int size;
}
