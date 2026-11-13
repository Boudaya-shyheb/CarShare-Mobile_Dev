package com.carshare.api.auth;

import com.carshare.api.common.ApiException;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

/**
 * Checks, before an account is created or its email changed, that the address can be written to
 * (Abstract API, Email Reputation). It runs only on the server: the key never reaches the app.
 *
 * <p>What is refused: an address that is not well formed, a disposable one, and one the provider
 * says is UNDELIVERABLE. UNKNOWN or risky answers are accepted and logged. The check is a courtesy,
 * never a gate: no key, a slow provider (3 s), a rejected or exhausted key or any unreadable answer
 * means the check is skipped, with one warning per kind of problem, and sign-up goes on. Definitive
 * answers are cached for 24 hours so a retyped address costs no second call.
 *
 * <p>The API key is part of the request URL, so no exception message is ever logged (it would
 * contain the URL); only the kind of failure is.
 */
@Service
public class EmailVerificationService {
    private static final Logger log = LoggerFactory.getLogger(EmailVerificationService.class);
    private static final Duration CACHE_TTL = Duration.ofHours(24);
    private static final int CACHE_LIMIT = 5_000;

    private final RestClient http;
    private final String apiKey;
    private final String url;
    private final Clock clock;
    private final Map<String, Cached> cache = new ConcurrentHashMap<>();
    private final Set<String> warned = ConcurrentHashMap.newKeySet();

    @Autowired
    public EmailVerificationService(
            @Value("${carshare.email-verification.api-key:}") String apiKey,
            @Value("${carshare.email-verification.url:https://emailreputation.abstractapi.com/v1/}") String url,
            @Value("${carshare.email-verification.timeout-ms:3000}") int timeoutMs) {
        this(clientWithTimeout(timeoutMs), apiKey, url, Clock.systemUTC());
    }

    /** For tests: any {@link RestClient} (backed by a mock server), any clock. */
    EmailVerificationService(RestClient http, String apiKey, String url, Clock clock) {
        this.http = http;
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.url = url;
        this.clock = clock;
    }

    private static RestClient clientWithTimeout(int timeoutMs) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofMillis(timeoutMs));
        factory.setReadTimeout(Duration.ofMillis(timeoutMs));
        return RestClient.builder().requestFactory(factory).build();
    }

    public boolean isEnabled() {
        return !apiKey.isEmpty();
    }

    @EventListener(ApplicationReadyEvent.class)
    public void report() {
        log.info(isEnabled()
                ? "Email verification: enabled"
                : "Email verification: disabled (no ABSTRACT_EMAIL_API_KEY): sign-up accepts any well-formed address");
    }

    /** Throws a 400 {@link ApiException} (with a {@code suggestion} when there is one) for a refused address. */
    public void verify(String email) {
        if (!isEnabled() || email == null || email.isBlank()) {
            return;
        }
        String address = email.trim().toLowerCase(Locale.ROOT);
        Outcome outcome = lookup(address);
        if (outcome != null && outcome.rejection() != null) {
            String suggestion = outcome.suggestion() != null && outcome.suggestion().equalsIgnoreCase(address)
                    ? null
                    : outcome.suggestion();
            throw rejection(new Outcome(outcome.rejection(), suggestion));
        }
    }

    private Outcome lookup(String address) {
        Instant now = clock.instant();
        Cached cached = cache.get(address);
        if (cached != null && cached.expires().isAfter(now)) {
            return cached.outcome();
        }
        String body;
        try {
            body = http.get()
                    .uri(url + "?api_key={key}&email={email}", apiKey, address)
                    .retrieve()
                    .body(String.class);
        } catch (RestClientResponseException error) {
            skip(failureKind(error.getStatusCode().value()));
            return null;
        } catch (RuntimeException error) {
            // A timeout or a refused connection. The message holds the URL, and so the key.
            skip("the provider did not answer in time (" + error.getClass().getSimpleName() + ")");
            return null;
        }
        Outcome outcome = evaluate(body, domainOf(address));
        if (outcome == null) {
            skip("the provider's answer could not be read");
            return null;
        }
        if (cache.size() >= CACHE_LIMIT) {
            cache.values().removeIf(entry -> !entry.expires().isAfter(now));
            if (cache.size() >= CACHE_LIMIT) {
                cache.clear();
            }
        }
        cache.put(address, new Cached(outcome, now.plus(CACHE_TTL)));
        return outcome;
    }

    /** Reads either answer shape: Email Reputation (current) or the older Email Validation fields. */
    Outcome evaluate(String body, String domain) {
        JsonObject json;
        try {
            JsonElement root = JsonParser.parseString(body == null ? "" : body);
            if (!root.isJsonObject()) {
                return null;
            }
            json = root.getAsJsonObject();
        } catch (RuntimeException error) {
            return null;
        }
        JsonObject deliverability = object(json, "email_deliverability");
        String status = lower(text(deliverability, "status"));
        if (status == null) {
            status = lower(text(json, "deliverability"));
        }
        String detail = lower(text(deliverability, "status_detail"));
        Boolean formatValid = bool(deliverability, "is_format_valid");
        if (formatValid == null) {
            formatValid = bool(object(json, "is_valid_format"), "value");
        }
        Boolean disposable = bool(object(json, "email_quality"), "is_disposable");
        if (disposable == null) {
            disposable = bool(object(json, "is_disposable_email"), "value");
        }
        String suggestion = text(json, "suggested_correction");
        if (suggestion == null) {
            suggestion = text(json, "autocorrect");
        }
        if (status == null && formatValid == null && disposable == null) {
            return null;
        }

        Rejection rejection = null;
        if (Boolean.FALSE.equals(formatValid) || "invalid_format".equals(detail)) {
            rejection = Rejection.INVALID;
        } else if (Boolean.TRUE.equals(disposable)) {
            rejection = Rejection.DISPOSABLE;
        } else if ("undeliverable".equals(status)) {
            rejection = Rejection.UNDELIVERABLE;
        } else if (!"deliverable".equals(status)) {
            log.info("Email verification: accepted an address at {} the provider could not confirm ({})",
                    domain, status == null ? "no status" : status);
        }
        return new Outcome(rejection, suggestion);
    }

    private static ApiException rejection(Outcome outcome) {
        String code;
        String message;
        switch (outcome.rejection()) {
            case INVALID -> {
                code = "email_invalid";
                message = "That email address doesn't look valid.";
            }
            case DISPOSABLE -> {
                code = "email_disposable";
                message = "Disposable email addresses aren't accepted. Use your permanent address.";
            }
            default -> {
                code = "email_undeliverable";
                message = "We couldn't find a mailbox for this address. Check it for typos.";
            }
        }
        // A typo such as gmial.com is often flagged as disposable or undeliverable; when the provider
        // knows the right spelling, say that instead of the generic reason.
        if (outcome.suggestion() != null) {
            message = "That email address looks mistyped.";
        }
        Map<String, Object> properties = outcome.suggestion() == null
                ? Map.of()
                : Map.of("suggestion", outcome.suggestion());
        return new ApiException(HttpStatus.BAD_REQUEST, code, message, properties);
    }

    private static String failureKind(int status) {
        return switch (status) {
            case 401 -> "the API key was rejected (401)";
            case 403, 422 -> "the quota is used up (" + status + ")";
            case 429 -> "the provider is rate limiting (429)";
            default -> "the provider answered with an error (" + status + ")";
        };
    }

    /** One warning per kind of problem, so a long outage does not flood the log. */
    private void skip(String reason) {
        if (warned.add(reason)) {
            log.warn("Email verification skipped, sign-up continues: {}", reason);
        }
    }

    private static String domainOf(String address) {
        int at = address.lastIndexOf('@');
        return at < 0 ? "?" : address.substring(at + 1);
    }

    private static JsonObject object(JsonObject parent, String name) {
        if (parent == null) {
            return null;
        }
        JsonElement value = parent.get(name);
        return value != null && value.isJsonObject() ? value.getAsJsonObject() : null;
    }

    private static String text(JsonObject parent, String name) {
        if (parent == null) {
            return null;
        }
        JsonElement value = parent.get(name);
        if (value == null || !value.isJsonPrimitive()) {
            return null;
        }
        String clean = value.getAsString().trim();
        return clean.isEmpty() ? null : clean;
    }

    private static Boolean bool(JsonObject parent, String name) {
        if (parent == null) {
            return null;
        }
        JsonElement value = parent.get(name);
        if (value == null || !value.isJsonPrimitive()) {
            return null;
        }
        String raw = value.getAsString();
        return "true".equalsIgnoreCase(raw) ? Boolean.TRUE : "false".equalsIgnoreCase(raw) ? Boolean.FALSE : null;
    }

    private static String lower(String value) {
        return value == null ? null : value.toLowerCase(Locale.ROOT);
    }

    enum Rejection { INVALID, DISPOSABLE, UNDELIVERABLE }

    record Outcome(Rejection rejection, String suggestion) { }

    private record Cached(Outcome outcome, Instant expires) { }
}
