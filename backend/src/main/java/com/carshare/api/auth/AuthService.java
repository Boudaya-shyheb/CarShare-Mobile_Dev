package com.carshare.api.auth;

import com.carshare.api.common.ApiException;
import com.carshare.api.security.SecurityProperties;
import com.carshare.api.security.TokenUtil;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Locale;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {
    private final UserRepository users;
    private final AuthSessionRepository sessions;
    private final PasswordResetTokenRepository resetTokens;
    private final PasswordEncoder passwordEncoder;
    private final SecurityProperties securityProperties;
    private final ResetMailService resetMailService;

    public AuthService(UserRepository users, AuthSessionRepository sessions,
            PasswordResetTokenRepository resetTokens, PasswordEncoder passwordEncoder,
            SecurityProperties securityProperties, ResetMailService resetMailService) {
        this.users = users;
        this.sessions = sessions;
        this.resetTokens = resetTokens;
        this.passwordEncoder = passwordEncoder;
        this.securityProperties = securityProperties;
        this.resetMailService = resetMailService;
    }

    @Transactional
    public AuthDtos.AuthResponse signUp(AuthDtos.SignUpRequest request) {
        if (!request.password().equals(request.confirmPassword())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "password_mismatch", "Passwords do not match.");
        }
        String email = normalizeEmail(request.email());
        if (users.existsByEmail(email)) {
            throw new ApiException(HttpStatus.CONFLICT, "email_in_use", "An account already exists for this email.");
        }
        String phone = normalizePhone(request.phone());
        validatePhone(phone);
        if (users.existsByNormalizedPhone(phone)) {
            throw new ApiException(HttpStatus.CONFLICT, "phone_in_use", "An account already exists for this phone number.");
        }
        AppUser user = users.save(new AppUser(request.fullName().trim(), phone, email,
                passwordEncoder.encode(request.password()), UserRole.valueOf(request.role().toUpperCase(Locale.ROOT))));
        return createSession(user);
    }

    @Transactional(noRollbackFor = ApiException.class)
    public AuthDtos.AuthResponse signIn(AuthDtos.SignInRequest request) {
        AppUser user = users.findByEmail(normalizeEmail(request.email()))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "invalid_credentials",
                        "The email or password is incorrect."));
        Instant now = Instant.now();
        if (user.hasActiveSignInLock(now)) {
            throw new ApiException(HttpStatus.LOCKED, "account_temporarily_locked",
                    "Too many incorrect attempts. Try again in 15 minutes.");
        }
        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            user.recordFailedSignIn(now);
            if (user.hasActiveSignInLock(now)) {
                throw new ApiException(HttpStatus.LOCKED, "account_temporarily_locked",
                        "Too many incorrect attempts. Try again in 15 minutes.");
            }
            throw new ApiException(HttpStatus.UNAUTHORIZED, "invalid_credentials",
                    "The email or password is incorrect.");
        }
        user.recordSuccessfulSignIn();
        return createSession(user);
    }

    @Transactional
    public void signOut(String tokenHash) {
        sessions.deleteByTokenHash(tokenHash);
    }

    @Transactional(readOnly = true)
    public AuthDtos.UserProfile getProfile(java.util.UUID userId) {
        return users.findById(userId).map(AuthDtos.UserProfile::from)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
    }

    @Transactional
    public AuthDtos.UserProfile updateProfile(UUID userId, AuthDtos.UpdateProfileRequest request) {
        AppUser user = users.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "account_not_found",
                        "Your account could not be found."));
        String email = normalizeEmail(request.email());
        users.findByEmail(email).filter(existing -> !existing.getId().equals(userId)).ifPresent(existing -> {
            throw new ApiException(HttpStatus.CONFLICT, "email_in_use",
                    "An account already exists for this email.");
        });
        String phone = normalizePhone(request.phone());
        validatePhone(phone);
        String currentPhone = normalizePhone(user.getPhone());
        if (!phone.equals(currentPhone) && users.existsByNormalizedPhoneAndIdNot(phone, userId)) {
            throw new ApiException(HttpStatus.CONFLICT, "phone_in_use", "An account already exists for this phone number.");
        }
        // Preserve the stored format when the normalized phone did not change.
        // This lets legacy accounts with duplicate phones still edit other fields.
        String phoneToSave = phone.equals(currentPhone) ? user.getPhone() : phone;
        user.updateProfile(request.fullName().trim(), phoneToSave, email,
                UserRole.valueOf(request.role().toUpperCase(Locale.ROOT)));
        return AuthDtos.UserProfile.from(user);
    }

    @Transactional
    public AuthDtos.MessageResponse forgotPassword(AuthDtos.ForgotPasswordRequest request) {
        String email = normalizeEmail(request.email());
        // Keep unknown addresses private; recovery availability is checked only for real users.
        var user = users.findByEmail(email);
        if (user.isPresent()) {
            String token = TokenUtil.newPasswordResetCode();
            resetTokens.deleteForUser(user.get().getId());
            resetTokens.save(new PasswordResetToken(user.get(), TokenUtil.sha256(token),
                    Instant.now().plus(securityProperties.resetTokenTtl())));
            resetMailService.sendPasswordReset(email, token);
        }
        return new AuthDtos.MessageResponse("If an account exists for this email, password reset instructions have been sent.");
    }

    @Transactional(noRollbackFor = ApiException.class)
    public AuthDtos.MessageResponse resetPassword(AuthDtos.ResetPasswordRequest request) {
        Instant now = Instant.now();
        PasswordResetToken token;
        if (request.email() != null && !request.email().isBlank()) {
            token = resetTokens.findFirstByUser_EmailAndExpiresAtAfter(normalizeEmail(request.email()), now)
                    .orElseThrow(() -> invalidResetCode());
            boolean valid = MessageDigest.isEqual(TokenUtil.sha256(request.token()).getBytes(StandardCharsets.US_ASCII),
                    token.getTokenHash().getBytes(StandardCharsets.US_ASCII));
            if (!valid) {
                token.recordFailedAttempt();
                if (token.getFailedAttempts() >= 5) resetTokens.delete(token);
                throw invalidResetCode();
            }
        } else {
            token = resetTokens.findByTokenHashAndExpiresAtAfter(TokenUtil.sha256(request.token()), now)
                    .orElseThrow(() -> invalidResetCode());
        }
        AppUser user = token.getUser();
        user.changePasswordHash(passwordEncoder.encode(request.newPassword()));
        resetTokens.deleteForUser(user.getId());
        sessions.deleteAllByUser_Id(user.getId());
        return new AuthDtos.MessageResponse("Your password has been reset. You can now sign in.");
    }

    @Transactional
    public void deleteAccount(UUID userId, String password) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "account_not_found", "Your account could not be found."));
        if (!passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "invalid_password", "The password is incorrect.");
        }
        users.delete(user);
    }

    private AuthDtos.AuthResponse createSession(AppUser user) {
        String rawToken = TokenUtil.newToken();
        Instant expiresAt = Instant.now().plus(securityProperties.sessionTtl());
        sessions.save(new AuthSession(user, TokenUtil.sha256(rawToken), expiresAt));
        return new AuthDtos.AuthResponse(rawToken, "Bearer", expiresAt, AuthDtos.UserProfile.from(user));
    }

    private static String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private static String normalizePhone(String phone) {
        return phone.trim().replaceAll("[\\s().-]", "");
    }

    private static void validatePhone(String phone) {
        if (!phone.matches("^\\+?[0-9]{7,15}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_phone", "Enter a valid phone number.");
        }
    }

    private static ApiException invalidResetCode() {
        return new ApiException(HttpStatus.BAD_REQUEST, "reset_code_invalid",
                "This reset code is invalid or has expired. Request a new code and try again.");
    }
}
