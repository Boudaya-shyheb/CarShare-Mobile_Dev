package com.carshare.api.common;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;
    public ApiException(HttpStatus status, String code, String message) {
        super(message); this.status = status; this.code = code;
    }
    public HttpStatus getStatus() { return status; }
    public String getCode() { return code; }
    public static ApiException unauthorized() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "invalid_credentials", "The email or password is incorrect.");
    }
}
