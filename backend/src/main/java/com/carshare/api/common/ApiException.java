package com.carshare.api.common;

import java.util.Map;
import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;
    private final Map<String, Object> properties;
    public ApiException(HttpStatus status, String code, String message) {
        this(status, code, message, Map.of());
    }
    /** {@code properties} become extra fields of the error body, next to {@code code}. */
    public ApiException(HttpStatus status, String code, String message, Map<String, Object> properties) {
        super(message); this.status = status; this.code = code; this.properties = Map.copyOf(properties);
    }
    public HttpStatus getStatus() { return status; }
    public String getCode() { return code; }
    public Map<String, Object> getProperties() { return properties; }
    public static ApiException unauthorized() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "invalid_credentials", "The email or password is incorrect.");
    }
}
