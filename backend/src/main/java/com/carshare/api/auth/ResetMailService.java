package com.carshare.api.auth;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.mail.MailException;
import org.springframework.stereotype.Service;
import com.carshare.api.common.ApiException;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Service
public class ResetMailService {
    private static final Logger logger = LoggerFactory.getLogger(ResetMailService.class);
    private static final Pattern SMTP_STATUS_PATTERN = Pattern.compile("(?<!\\d)([245]\\d{2})(?:[- ])");
    private final ObjectProvider<JavaMailSender> mailSenderProvider;
    private final String host;
    private final String from;

    public ResetMailService(ObjectProvider<JavaMailSender> mailSenderProvider,
            @Value("${spring.mail.host:}") String host,
            @Value("${carshare.mail.from:}") String from) {
        this.mailSenderProvider = mailSenderProvider;
        this.host = host;
        this.from = from;
    }

    public void sendPasswordReset(String email, String token) {
        JavaMailSender sender = mailSenderProvider.getIfAvailable();
        if (sender == null || host.isBlank() || from.isBlank()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "password_reset_unavailable",
                    "Password recovery is not configured yet. Please try again later.");
        }
        try {
            var message = sender.createMimeMessage();
            var helper = new MimeMessageHelper(message, true, StandardCharsets.UTF_8.name());
            helper.setFrom(from);
            helper.setTo(email);
            helper.setSubject("Reset your CarShare password");
            helper.setText(
                    "We received a request to reset your CarShare password.\n\n"
                            + "Your 6-digit reset code is: " + token + "\n\n"
                            + "Open the CarShare app, tap Forgot password, and enter this code with your new password. "
                            + "The code expires in 30 minutes and can only be used once.\n\n"
                            + "If you did not request this, you can ignore this email.",
                    "<html><body style=\"font-family:Arial,sans-serif;color:#172033\">"
                            + "<p>We received a request to reset your CarShare password.</p>"
                            + "<p>Your 6-digit reset code is:</p>"
                            + "<p style=\"font-size:28px;font-weight:bold;letter-spacing:5px;color:#059669\">"
                            + token + "</p>"
                            + "<p>Open the CarShare app, tap <b>Forgot password</b>, and enter this code "
                            + "with your new password. The code expires in 30 minutes and can only be used once.</p>"
                            + "<p>If you did not request this, you can ignore this email.</p>"
                            + "</body></html>");
            sender.send(message);
        } catch (jakarta.mail.MessagingException exception) {
            logger.warn("Password reset message could not be prepared ({}).", exception.getClass().getSimpleName());
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "password_reset_email_failed",
                    "We could not send the password reset email. Please try again later.");
        } catch (MailException exception) {
            Throwable cause = exception;
            while (cause.getCause() != null) cause = cause.getCause();
            Matcher statusMatcher = SMTP_STATUS_PATTERN.matcher(String.valueOf(cause.getMessage()));
            String smtpStatus = statusMatcher.find() ? statusMatcher.group(1) : "unavailable";
            logger.warn("Password reset SMTP delivery failed ({}; root cause {}; SMTP status {}).",
                    exception.getClass().getSimpleName(), cause.getClass().getSimpleName(), smtpStatus);
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "password_reset_email_failed",
                    "We could not send the password reset email. Please verify the email service settings and try again.");
        }
    }
}
