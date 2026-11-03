package com.carshare.api.auth;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import com.carshare.api.common.ApiException;

@Service
public class ResetMailService {
    private final ObjectProvider<JavaMailSender> mailSenderProvider;
    private final String host;
    private final String from;
    private final String publicBaseUrl;

    public ResetMailService(ObjectProvider<JavaMailSender> mailSenderProvider,
            @Value("${spring.mail.host:}") String host,
            @Value("${carshare.mail.from:}") String from,
            @Value("${carshare.mail.public-base-url}") String publicBaseUrl) {
        this.mailSenderProvider = mailSenderProvider;
        this.host = host;
        this.from = from;
        this.publicBaseUrl = publicBaseUrl.replaceAll("/+$", "");
    }

    public void sendPasswordReset(String email, String token) {
        JavaMailSender sender = mailSenderProvider.getIfAvailable();
        if (sender == null || host.isBlank() || from.isBlank()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "password_reset_unavailable",
                    "Password recovery is not configured yet. Please try again later.");
        }
        String resetUrl = publicBaseUrl + "/reset-password.html?token=" + token;
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(email);
        message.setSubject("Reset your CarShare password");
        message.setText("We received a request to reset your CarShare password. Open this link within 30 minutes:\n\n"
                + resetUrl + "\n\nIf you did not request this, you can ignore this email.");
        sender.send(message);
    }
}
