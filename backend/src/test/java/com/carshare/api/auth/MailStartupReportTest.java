package com.carshare.api.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class MailStartupReportTest {
    @Test
    @DisplayName("a host and a sender mean mail is configured, and only the host is named")
    void configured() {
        assertEquals("Mail configured (smtp.example.com)",
                MailStartupReport.describe("smtp.example.com", "no-reply@carshare.tn"));
    }

    @Test
    @DisplayName("nothing set, a missing host or a missing sender all read as not configured")
    void notConfigured() {
        String expected = "Mail not configured: password reset and email notifications disabled";

        assertEquals(expected, MailStartupReport.describe("", ""));
        assertEquals(expected, MailStartupReport.describe(null, null));
        assertEquals(expected, MailStartupReport.describe("smtp.example.com", ""));
        assertEquals(expected, MailStartupReport.describe("", "no-reply@carshare.tn"));
    }
}
