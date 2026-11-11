package com.carshare.api.auth;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.googleapis.javanet.GoogleNetHttpTransport;
import com.google.api.client.json.gson.GsonFactory;
import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.List;
import java.util.Locale;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;

@Service
public class SocialAuthService {
    private final UserRepository users;
    private final UserAuthIdentityRepository identities;
    private final AuthService auth;
    private final org.springframework.security.crypto.password.PasswordEncoder passwords;
    private final RestClient http = RestClient.create();
    private final String googleClientId;
    private final String facebookAppId;
    private final String facebookAppSecret;

    public SocialAuthService(UserRepository users, UserAuthIdentityRepository identities, AuthService auth,
            org.springframework.security.crypto.password.PasswordEncoder passwords,
            @Value("${carshare.auth.google-client-id:}") String googleClientId,
            @Value("${carshare.auth.facebook-app-id:}") String facebookAppId,
            @Value("${carshare.auth.facebook-app-secret:}") String facebookAppSecret) {
        this.users = users;
        this.identities = identities;
        this.auth = auth;
        this.passwords = passwords;
        this.googleClientId = googleClientId;
        this.facebookAppId = facebookAppId;
        this.facebookAppSecret = facebookAppSecret;
    }

    @Transactional
    public AuthDtos.AuthResponse google(SocialLoginRequest request) {
        if (googleClientId.isBlank()) throw providerNotConfigured("Google");
        GoogleIdToken.Payload payload;
        try {
            var transport = GoogleNetHttpTransport.newTrustedTransport();
            var verifier = new GoogleIdTokenVerifier.Builder(transport, GsonFactory.getDefaultInstance())
                    .setAudience(List.of(googleClientId)).build();
            GoogleIdToken token = verifier.verify(request.token());
            if (token == null || !Boolean.TRUE.equals(token.getPayload().getEmailVerified())) {
                throw invalidToken();
            }
            payload = token.getPayload();
        } catch (GeneralSecurityException | IOException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "google_verification_unavailable",
                    "Google could not be reached to verify the sign-in. Please try again.");
        }
        String name = (String) payload.get("name");
        return complete("google", payload.getSubject(), payload.getEmail(), name, request);
    }

    @Transactional
    public AuthDtos.AuthResponse facebook(SocialLoginRequest request) {
        if (facebookAppId.isBlank() || facebookAppSecret.isBlank()) throw providerNotConfigured("Facebook");
        JsonObject debug;
        try {
            var form = new LinkedMultiValueMap<String, String>();
            form.add("input_token", request.token());
            form.add("access_token", facebookAppId + "|" + facebookAppSecret);
            String response = http.post().uri("https://graph.facebook.com/v22.0/debug_token")
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED).body(form)
                    .retrieve().body(String.class);
            debug = JsonParser.parseString(response == null ? "{}" : response).getAsJsonObject();
        } catch (RuntimeException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "facebook_verification_unavailable",
                    "Facebook could not be reached to verify the sign-in. Please try again.");
        }
        JsonObject data = debug == null ? null : debug.getAsJsonObject("data");
        if (data == null || !data.has("is_valid") || !data.get("is_valid").getAsBoolean()
                || !facebookAppId.equals(data.get("app_id").getAsString())) throw invalidToken();

        JsonObject profile;
        try {
            String response = http.get().uri("https://graph.facebook.com/v22.0/me?fields=id,name,email")
                    .header("Authorization", "Bearer " + request.token()).retrieve().body(String.class);
            profile = JsonParser.parseString(response == null ? "{}" : response).getAsJsonObject();
        } catch (RuntimeException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "facebook_profile_unavailable",
                    "Facebook profile information could not be loaded. Please try again.");
        }
        String subject = jsonValue(profile, "id");
        String email = jsonValue(profile, "email");
        String name = jsonValue(profile, "name");
        if (subject.isBlank() || email.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "social_email_required",
                    "Facebook did not provide an email address. Sign up with email and password instead.");
        }
        return complete("facebook", subject, email, name, request);
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

    private String jsonValue(JsonObject value, String key) {
        return value == null || !value.has(key) || value.get(key).isJsonNull() ? "" : value.get(key).getAsString();
    }

    public record SocialLoginRequest(String token, String phone, String role) { }
}
