package com.carshare.api.auth;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.gson.GsonFactory;
import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.util.List;
import java.util.Locale;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SocialAuthService {
    private static final Logger logger = LoggerFactory.getLogger(SocialAuthService.class);
    private final UserRepository users;
    private final UserAuthIdentityRepository identities;
    private final AuthService auth;
    private final org.springframework.security.crypto.password.PasswordEncoder passwords;
    private final String googleClientId;
    private volatile GoogleIdTokenVerifier googleVerifier;

    public SocialAuthService(UserRepository users, UserAuthIdentityRepository identities, AuthService auth,
            org.springframework.security.crypto.password.PasswordEncoder passwords,
            @Value("${carshare.auth.google-client-id:}") String googleClientId) {
        this.users = users;
        this.identities = identities;
        this.auth = auth;
        this.passwords = passwords;
        this.googleClientId = googleClientId;
    }

    @Transactional
    public AuthDtos.AuthResponse google(SocialLoginRequest request) {
        if (googleClientId.isBlank()) throw providerNotConfigured("Google");
        GoogleIdToken.Payload payload;
        try {
            GoogleIdToken token = googleVerifier().verify(request.token());
            if (token == null || !Boolean.TRUE.equals(token.getPayload().getEmailVerified())) {
                throw invalidToken();
            }
            payload = token.getPayload();
        } catch (GeneralSecurityException | IOException exception) {
            Throwable cause = exception;
            while (cause.getCause() != null) cause = cause.getCause();
            logger.warn("Google ID-token verification could not load signing keys ({}: {}).",
                    cause.getClass().getSimpleName(), cause.getMessage());
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "google_verification_unavailable",
                    "Google could not be reached to verify the sign-in. Please try again.");
        }
        String name = (String) payload.get("name");
        return complete("google", payload.getSubject(), payload.getEmail(), name, request);
    }

    private GoogleIdTokenVerifier googleVerifier() throws GeneralSecurityException, IOException {
        GoogleIdTokenVerifier verifier = googleVerifier;
        if (verifier == null) {
            synchronized (this) {
                verifier = googleVerifier;
                if (verifier == null) {
                    var transport = googleTransport();
                    verifier = new GoogleIdTokenVerifier.Builder(transport, GsonFactory.getDefaultInstance())
                            .setAudience(List.of(googleClientId)).build();
                    googleVerifier = verifier;
                }
            }
        }
        return verifier;
    }

    private NetHttpTransport googleTransport() throws GeneralSecurityException, IOException {
        if (System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("win")) {
            KeyStore windowsRoot = KeyStore.getInstance("Windows-ROOT");
            windowsRoot.load(null, null);
            TrustManagerFactory trustManagers = TrustManagerFactory.getInstance(
                    TrustManagerFactory.getDefaultAlgorithm());
            trustManagers.init(windowsRoot);
            SSLContext sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, trustManagers.getTrustManagers(), null);
            return new NetHttpTransport.Builder()
                    .setSslSocketFactory(sslContext.getSocketFactory())
                    .build();
        }
        return new NetHttpTransport.Builder().build();
    }

    private AuthDtos.AuthResponse complete(String provider, String subject, String email, String name,
            SocialLoginRequest request) {
        if (subject == null || subject.isBlank() || email == null || email.isBlank()) throw invalidToken();
        var existingIdentity = identities.findByProviderAndProviderSubject(provider, subject);
        if (existingIdentity.isPresent()) return auth.createSession(existingIdentity.get().getUser());

        String normalizedEmail = email.trim().toLowerCase(Locale.ROOT);
        AppUser user = users.findByEmail(normalizedEmail).orElse(null);
        if (user == null) {
            String phone = request.phone() == null ? "" : request.phone().trim().replaceAll("[\\s().-]", "");
            if (phone.isBlank() || request.role() == null || request.role().isBlank()) {
                throw new ApiException(HttpStatus.PRECONDITION_REQUIRED, "social_profile_required",
                        "Add your phone number and choose passenger or driver to finish creating your account.");
            }
            if (!phone.matches("^\\+?[0-9]{7,15}$")) throw new ApiException(HttpStatus.BAD_REQUEST,
                    "invalid_phone", "Enter a valid phone number.");
            if (users.existsByNormalizedPhone(phone)) throw new ApiException(HttpStatus.CONFLICT,
                    "phone_in_use", "An account already exists for this phone number.");
            UserRole role;
            try { role = UserRole.valueOf(request.role().trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException exception) { throw new ApiException(HttpStatus.BAD_REQUEST,
                    "invalid_role", "Choose passenger or driver."); }
            if (role == UserRole.ADMIN) throw new ApiException(HttpStatus.BAD_REQUEST,
                    "invalid_role", "Choose passenger or driver.");
            String safeName = name == null || name.isBlank() ? normalizedEmail.substring(0, normalizedEmail.indexOf('@')) : name.trim();
            user = users.save(new AppUser(safeName, phone, normalizedEmail,
                    passwords.encode(java.util.UUID.randomUUID().toString()), role));
        }
        try {
            identities.saveAndFlush(new UserAuthIdentity(user, provider, subject));
        } catch (DataIntegrityViolationException exception) {
            throw new ApiException(HttpStatus.CONFLICT, "social_account_linked",
                    "This social account is already linked to another CarShare profile.");
        }
        return auth.createSession(user);
    }

    private ApiException providerNotConfigured(String name) {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "social_provider_not_configured",
                name + " sign-in is not configured yet. Add the provider credentials to the backend and app settings.");
    }

    private ApiException invalidToken() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "invalid_social_token",
                "The social sign-in could not be verified. Please try again.");
    }

    public record SocialLoginRequest(String token, String phone, String role) { }
}
