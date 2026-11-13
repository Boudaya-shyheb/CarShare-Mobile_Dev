package com.carshare.api.auth;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.carshare.api.common.ApiException;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * The email check against a mocked HTTP server: no test ever reaches the real provider, and the
 * fake key below is not a real one.
 */
class EmailVerificationServiceTest {

    private static final String URL = "https://email.test/v1/";

    private final AtomicReference<Instant> now = new AtomicReference<>(Instant.parse("2026-11-13T10:00:00Z"));
    private final Clock clock = new Clock() {
        @Override public java.time.ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(java.time.ZoneId zone) { return this; }
        @Override public Instant instant() { return now.get(); }
    };

    private MockRestServiceServer server;

    private EmailVerificationService service(String key) {
        RestClient.Builder builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        return new EmailVerificationService(builder.build(), key, URL, clock);
    }

    private static String reputation(String status, String detail, boolean formatValid,
            boolean disposable, String suggestion) {
        return """
                {"email_address":"x","suggested_correction":%s,
                 "email_deliverability":{"status":"%s","status_detail":"%s","is_format_valid":%s,
                   "is_smtp_valid":true,"is_mx_valid":true},
                 "email_quality":{"score":0.8,"is_disposable":%s,"is_free_email":true},
                 "email_risk":{"address_risk_status":"low"}}
                """.formatted(suggestion == null ? "null" : "\"" + suggestion + "\"",
                status, detail, formatValid, disposable);
    }

    private void answer(String body) {
        server.expect(requestTo(org.hamcrest.Matchers.startsWith(URL)))
                .andExpect(queryParam("api_key", "test-key"))
                .andRespond(withSuccess(body, MediaType.APPLICATION_JSON));
    }

    @Test
    @DisplayName("a deliverable address is accepted, and the key and address are sent as query parameters")
    void deliverableIsAccepted() {
        EmailVerificationService service = service("test-key");
        server.expect(requestTo(URL + "?api_key=test-key&email=yacine%40example.com"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess(reputation("deliverable", "valid_email", true, false, null),
                        MediaType.APPLICATION_JSON));

        assertDoesNotThrow(() -> service.verify("Yacine@Example.com"));
        server.verify();
    }

    private static org.springframework.test.web.client.RequestMatcher method(HttpMethod method) {
        return org.springframework.test.web.client.match.MockRestRequestMatchers.method(method);
    }

    @Test
    @DisplayName("a disposable address is refused with email_disposable")
    void disposableIsRefused() {
        EmailVerificationService service = service("test-key");
        answer(reputation("deliverable", "valid_email", true, true, null));

        ApiException error = assertThrows(ApiException.class, () -> service.verify("a@mailinator.com"));

        assertEquals("email_disposable", error.getCode());
        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertTrue(error.getProperties().isEmpty());
    }

    @Test
    @DisplayName("an undeliverable address is refused, with the provider's suggested correction")
    void undeliverableComesWithASuggestion() {
        EmailVerificationService service = service("test-key");
        answer(reputation("undeliverable", "dns_record_not_found", true, false, "test@gmail.com"));

        ApiException error = assertThrows(ApiException.class, () -> service.verify("test@gmial.com"));

        assertEquals("email_undeliverable", error.getCode());
        assertEquals("test@gmail.com", error.getProperties().get("suggestion"));
        assertEquals("That email address looks mistyped.", error.getMessage());
    }

    @Test
    @DisplayName("a malformed address is refused with email_invalid")
    void invalidFormatIsRefused() {
        EmailVerificationService service = service("test-key");
        answer(reputation("undeliverable", "invalid_format", false, false, null));

        ApiException error = assertThrows(ApiException.class, () -> service.verify("johnsmith@x"));

        assertEquals("email_invalid", error.getCode());
    }

    @Test
    @DisplayName("UNKNOWN and risky answers are accepted")
    void unknownIsAccepted() {
        EmailVerificationService service = service("test-key");
        answer(reputation("unknown", "unavailable_server", true, false, null));

        assertDoesNotThrow(() -> service.verify("someone@corporate.example"));
    }

    @Test
    @DisplayName("the older Email Validation answer shape is read too")
    void legacyShapeIsRead() {
        EmailVerificationService service = service("test-key");
        answer("""
                {"email":"a@b.c","autocorrect":"a@gmail.com","deliverability":"UNDELIVERABLE",
                 "is_valid_format":{"value":true},"is_disposable_email":{"value":false}}
                """);

        ApiException error = assertThrows(ApiException.class, () -> service.verify("a@gmial.com"));

        assertEquals("email_undeliverable", error.getCode());
        assertEquals("a@gmail.com", error.getProperties().get("suggestion"));
    }

    @Test
    @DisplayName("a suggestion equal to the address is not offered back")
    void identicalSuggestionIsDropped() {
        EmailVerificationService service = service("test-key");
        answer(reputation("undeliverable", "invalid_mailbox", true, false, "x@y.com"));

        ApiException error = assertThrows(ApiException.class, () -> service.verify("x@y.com"));

        assertFalse(error.getProperties().containsKey("suggestion"));
    }

    @Test
    @DisplayName("no key: the check is off and nothing is called")
    void noKeyMeansNoCheck() {
        EmailVerificationService service = service("  ");

        assertFalse(service.isEnabled());
        assertDoesNotThrow(() -> service.verify("whoever@mailinator.com"));
        server.verify();
    }

    @Test
    @DisplayName("quota used up, rejected key, rate limit and server errors never block sign-up")
    void providerErrorsAreSkipped() {
        for (HttpStatus status : new HttpStatus[] {HttpStatus.UNPROCESSABLE_CONTENT, HttpStatus.FORBIDDEN,
                HttpStatus.UNAUTHORIZED, HttpStatus.TOO_MANY_REQUESTS, HttpStatus.INTERNAL_SERVER_ERROR}) {
            EmailVerificationService service = service("test-key");
            server.expect(requestTo(org.hamcrest.Matchers.startsWith(URL))).andRespond(withStatus(status));

            assertDoesNotThrow(() -> service.verify("a@b.com"), status.toString());
        }
    }

    @Test
    @DisplayName("a timeout or a dropped connection never blocks sign-up")
    void networkFailureIsSkipped() {
        EmailVerificationService service = service("test-key");
        server.expect(requestTo(org.hamcrest.Matchers.startsWith(URL)))
                .andRespond(request -> { throw new IOException("timed out"); });

        assertDoesNotThrow(() -> service.verify("a@b.com"));
    }

    @Test
    @DisplayName("an unreadable answer is skipped, not cached")
    void garbageIsSkipped() {
        EmailVerificationService service = service("test-key");
        answer("<html>maintenance</html>");
        assertDoesNotThrow(() -> service.verify("a@b.com"));

        server.reset();
        answer(reputation("undeliverable", "invalid_mailbox", true, false, null));
        assertThrows(ApiException.class, () -> service.verify("a@b.com"));
    }

    @Test
    @DisplayName("an answer is cached for 24 hours: the second check makes no call, the one after a day does")
    void answersAreCachedForADay() {
        EmailVerificationService service = service("test-key");
        server.expect(ExpectedCount.once(), requestTo(org.hamcrest.Matchers.startsWith(URL)))
                .andRespond(withSuccess(reputation("undeliverable", "invalid_mailbox", true, false, null),
                        MediaType.APPLICATION_JSON));

        assertThrows(ApiException.class, () -> service.verify("cached@b.com"));
        assertThrows(ApiException.class, () -> service.verify("CACHED@b.com"));
        server.verify();

        now.set(now.get().plus(Duration.ofHours(25)));
        server.reset();
        server.expect(ExpectedCount.once(), requestTo(org.hamcrest.Matchers.startsWith(URL)))
                .andRespond(withSuccess(reputation("deliverable", "valid_email", true, false, null),
                        MediaType.APPLICATION_JSON));
        assertDoesNotThrow(() -> service.verify("cached@b.com"));
        server.verify();
    }

    @Test
    @DisplayName("failures are not cached: the next sign-up asks again")
    void failuresAreNotCached() {
        EmailVerificationService service = service("test-key");
        server.expect(requestTo(org.hamcrest.Matchers.startsWith(URL))).andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));
        assertDoesNotThrow(() -> service.verify("again@b.com"));

        server.reset();
        server.expect(requestTo(org.hamcrest.Matchers.startsWith(URL)))
                .andRespond(withSuccess(reputation("undeliverable", "invalid_mailbox", true, false, null),
                        MediaType.APPLICATION_JSON));
        assertThrows(ApiException.class, () -> service.verify("again@b.com"));
    }
}
