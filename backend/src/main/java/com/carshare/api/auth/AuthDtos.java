package com.carshare.api.auth;

import com.carshare.api.users.AppUser;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.UUID;

public final class AuthDtos {
    private AuthDtos() { }
    public record SignUpRequest(@NotBlank @Size(max = 100) String fullName,
            @NotBlank @Size(max = 24) @Pattern(regexp = "^\\+?[0-9][0-9\\s().-]{5,19}$") String phone,
            @NotBlank @Email @Size(max = 254) String email,
            @NotBlank @Size(min = 8, max = 72) String password,
            @NotBlank String confirmPassword,
            @NotBlank @Pattern(regexp = "^(passenger|driver)$") String role) { }
    public record SignInRequest(@NotBlank @Email @Size(max = 254) String email, @NotBlank String password) { }
    public record UpdateProfileRequest(@NotBlank @Size(max = 100) String fullName,
            @NotBlank @Size(max = 24) @Pattern(regexp = "^\\+?[0-9][0-9\\s().-]{5,19}$") String phone,
            @NotBlank @Email @Size(max = 254) String email,
            @NotBlank @Pattern(regexp = "^(passenger|driver|admin)$") String role) { }
    public record ForgotPasswordRequest(@NotBlank @Email @Size(max = 254) String email) { }
    public record ResetPasswordRequest(@Email @Size(max = 254) String email, @NotBlank String token,
            @NotBlank @Size(min = 8, max = 72) String newPassword) { }
    public record DeleteAccountRequest(@NotBlank String password) { }
    public record AdminUpdateUserRequest(@NotBlank @Size(max = 100) String fullName,
            @NotBlank @Size(max = 24) @Pattern(regexp = "^\\+?[0-9][0-9\\s().-]{5,19}$") String phone,
            @NotBlank @Email @Size(max = 254) String email,
            @NotBlank @Pattern(regexp = "^(passenger|driver|admin)$") String role) { }
    public record AdminStatusRequest(@NotBlank @Pattern(regexp = "^(ACTIVE|WARNING|SUSPENDED|BANNED)$") String status,
            Instant statusUntil, @NotBlank @Size(max = 500) String reason) { }
    public record EmergencyContactRequest(@NotBlank @Size(max = 100) String name,
            @NotBlank @Size(max = 24) @Pattern(regexp = "^\\+?[0-9][0-9\\s().-]{5,19}$") String phone,
            @NotBlank @Size(max = 40) String relationship) { }
    public record EmergencyContact(UUID id, String name, String phone, String relationship) {
        public static EmergencyContact from(com.carshare.api.users.UserEmergencyContact contact) {
            return new EmergencyContact(contact.getId(), contact.getName(), contact.getPhone(), contact.getRelationship());
        }
    }
    public record UpdatePreferences(@NotBlank @Size(max = 10) String language,
            @Size(max = 180) String homePlace, @Size(max = 180) String workPlace,
            @Size(max = 180) String campusPlace, boolean musicAllowed, boolean smokingAllowed,
            boolean petsAllowed, @NotBlank @Size(max = 20) String luggagePreference) { }
    public record Preferences(UUID userId, String language, String homePlace, String workPlace,
            String campusPlace, boolean musicAllowed, boolean smokingAllowed, boolean petsAllowed,
            String luggagePreference, Instant updatedAt) {
        public static Preferences defaults(UUID userId) {
            return new Preferences(userId, "en", null, null, null, true, false, false, "standard", null);
        }
        public static Preferences from(com.carshare.api.users.UserPreferences value) {
            return new Preferences(value.getUserId(), value.getLanguage(), value.getHomePlace(),
                    value.getWorkPlace(), value.getCampusPlace(), value.isMusicAllowed(),
                    value.isSmokingAllowed(), value.isPetsAllowed(), value.getLuggagePreference(), value.getUpdatedAt());
        }
    }
    public record Sanction(UUID id, int points, String reason, Instant issuedAt, Instant expiresAt,
            boolean active) {
        public static Sanction from(com.carshare.api.users.UserSanction value, Instant now) {
            return new Sanction(value.getId(), value.getPoints(), value.getReason(), value.getIssuedAt(),
                    value.getExpiresAt(), value.getExpiresAt().isAfter(now));
        }
    }
    public record ProfilePhoto(byte[] bytes, String contentType) { }
    public record UserProfile(UUID id, String fullName, String phone, String email, String role, Instant createdAt,
            String status, Instant statusUntil, boolean hasProfilePhoto,
            java.time.LocalDate driverLicenseExpiry, String driverLicenseStatus,
            String driverLicenseReviewReason) {
        public static UserProfile from(AppUser user) {
            return new UserProfile(user.getId(), user.getFullName(), user.getPhone(), user.getEmail(),
                    user.getRole().value(), user.getCreatedAt(), user.getAccountStatus().name(),
                    user.getStatusUntil(), user.getProfilePhoto() != null,
                    user.getDriverLicenseExpiry(), user.getDriverLicenseStatus(), user.getDriverLicenseReviewReason());
        }
    }
    public record AdminUser(UUID id, String fullName, String phone, String email, String role,
            Instant createdAt, String status, Instant statusUntil, String statusReason,
            boolean hasProfilePhoto, java.time.LocalDate driverLicenseExpiry,
            String driverLicenseStatus, String driverLicenseReviewReason) {
        public static AdminUser from(AppUser user) {
            return new AdminUser(user.getId(), user.getFullName(), user.getPhone(), user.getEmail(),
                    user.getRole().value(), user.getCreatedAt(), user.getAccountStatus().name(),
                    user.getStatusUntil(), user.getStatusReason(), user.getProfilePhoto() != null,
                    user.getDriverLicenseExpiry(), user.getDriverLicenseStatus(),
                    user.getDriverLicenseReviewReason());
        }
    }
    public record AuthResponse(String accessToken, String tokenType, Instant expiresAt, UserProfile user) { }
    public record MessageResponse(String message) { }
}
