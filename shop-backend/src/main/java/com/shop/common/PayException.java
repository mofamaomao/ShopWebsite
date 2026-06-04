package com.shop.common;

public class PayException extends RuntimeException {

    private final int code;

    public PayException(String message) {
        super(message);
        this.code = 400;
    }

    public PayException(int code, String message) {
        super(message);
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
