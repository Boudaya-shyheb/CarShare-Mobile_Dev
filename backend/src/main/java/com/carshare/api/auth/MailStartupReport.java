package com.carshare.api.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Says once, at startup, whether email can be sent. Mail is optional: with nothing configured the
 * API still runs and only the features that need it (password reset) answer "not configured".
 * Only the host is logged, never the username or password.
 */
@Component
public class MailStartupReport {
    private static final Logger log = LoggerFactory.getLogger(MailStartupReport.class);

    private final String host;
    private final String from;

    public MailStartupReport(@Value("${spring.mail.host:}") String host,
            @Value("${carshare.mail.from:}") String from) {
        this.host = host;
        this.from = from;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void report() {
        log.info(describe(host, from));
    }

    /** Configured means a host and a sender, the same test the reset mail itself applies. */
    static String describe(String host, String from) {
        if (host == null || host.isBlank() || from == null || from.isBlank()) {
            return "Mail not configured: password reset and email notifications disabled";
        }
        return "Mail configured (" + host.trim() + ")";
    }
}
