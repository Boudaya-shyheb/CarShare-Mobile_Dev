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
            @NotBlank @Pattern(regexp = "^(passenger|driver)$") String role) { }
    public record ForgotPasswordRequest(@NotBlank @Email @Size(max = 254) String email) { }
    public record ResetPasswordRequest(@NotBlank String token, @NotBlank @Size(min = 8, max = 72) String newPassword) { }
    public record UserProfile(UUID id, String fullName, String phone, String email, String role, Instant createdAt) {
        public static UserProfile from(AppUser user) {
            return new UserProfile(user.getId(), user.getFullName(), user.getPhone(), user.getEmail(),
                    user.getRole().value(), user.getCreatedAt());
        }
    }
    public record AuthResponse(String accessToken, String tokenType, Instant expiresAt, UserProfile user) { }
    public record MessageResponse(String message) { }
}
