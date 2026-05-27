package com.shop.exception;

import com.shop.common.BusinessException;
import com.shop.common.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public Result<?> handleBusiness(BusinessException e) {
        return Result.fail(e.getCode(), e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<?> handleValidation(MethodArgumentNotValidException e) {
        String msg = e.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining("; "));
        return Result.fail(400, msg);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public Result<?> handleBadJson(HttpMessageNotReadableException e) {
        return Result.fail(400, "请求体 JSON 格式错误: " + e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    public Result<?> handleGeneral(Exception e) {
        log.error("unhandled exception: {}", e.getMessage(), e);
        return Result.fail(500, "服务器内部错误: " + e.getMessage());
    }
}
