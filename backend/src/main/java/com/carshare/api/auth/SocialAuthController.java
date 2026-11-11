package com.carshare.api.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth/social")
public class SocialAuthController {
    private final SocialAuthService socialAuth;
    public SocialAuthController(SocialAuthService socialAuth) { this.socialAuth = socialAuth; }

    @PostMapping("/google")
    public AuthDtos.AuthResponse google(@Valid @RequestBody SocialLoginBody request) {
        return socialAuth.google(request.toRequest());
    }

    @PostMapping("/facebook")
    public AuthDtos.AuthResponse facebook(@Valid @RequestBody SocialLoginBody request) {
        return socialAuth.facebook(request.toRequest());
    }

    public record SocialLoginBody(@NotBlank String token, @Size(max=24) String phone,
            @Size(max=16) String role) {
        SocialAuthService.SocialLoginRequest toRequest() {
            return new SocialAuthService.SocialLoginRequest(token, phone, role);
        }
    }
}
