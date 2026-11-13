package com.carshare.api.common;

import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.mail.MailException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import jakarta.servlet.http.HttpServletRequest;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(ApiException.class)
    ProblemDetail handleApiException(ApiException exception) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(exception.getStatus(), exception.getMessage());
        detail.setProperty("code", exception.getCode());
        exception.getProperties().forEach(detail::setProperty);
        return detail;
    }
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ProblemDetail handleValidation(MethodArgumentNotValidException exception) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Please check the information you entered.");
        detail.setProperty("code", "validation_error");
        return detail;
    }
    @ExceptionHandler(DataIntegrityViolationException.class)
    ProblemDetail handleConflict(DataIntegrityViolationException exception) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, "This email or phone number is already registered.");
        detail.setProperty("code", "email_already_in_use");
        return detail;
    }
    @ExceptionHandler({DataAccessException.class, MailException.class})
    ProblemDetail handleInfrastructure(Exception exception) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE,
                "The service is temporarily unavailable. Please try again later.");
        detail.setProperty("code", "service_unavailable");
        return detail;
    }
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ProblemDetail handleUploadTooLarge(
            MaxUploadSizeExceededException exception, HttpServletRequest request) {
        String message = request.getRequestURI().endsWith("/users/me/photo")
                ? "Profile photos must be 2 MB or smaller."
                : "Each vehicle photo must be 5 MB or smaller.";
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                message);
        detail.setProperty("code", "invalid_photo_size");
        return detail;
    }
}
