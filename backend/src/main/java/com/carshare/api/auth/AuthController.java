package com.carshare.api.auth;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class AuthController {
    private final AuthService authService;
    public AuthController(AuthService authService) { this.authService = authService; }

    @PostMapping("/auth/signup")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthDtos.AuthResponse signUp(@Valid @RequestBody AuthDtos.SignUpRequest request) {
        return authService.signUp(request);
    }

    @PostMapping("/auth/signin")
    public AuthDtos.AuthResponse signIn(@Valid @RequestBody AuthDtos.SignInRequest request) {
        return authService.signIn(request);
    }

    @PostMapping("/auth/signout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void signOut(@AuthenticationPrincipal SessionPrincipal principal) {
        authService.signOut(principal.tokenHash());
    }

    @PostMapping("/auth/forgot-password")
    public AuthDtos.MessageResponse forgotPassword(@Valid @RequestBody AuthDtos.ForgotPasswordRequest request) {
        return authService.forgotPassword(request);
    }

    @PostMapping("/auth/reset-password")
    public AuthDtos.MessageResponse resetPassword(@Valid @RequestBody AuthDtos.ResetPasswordRequest request) {
        return authService.resetPassword(request);
    }

    @GetMapping("/users/me")
    public AuthDtos.UserProfile currentUser(@AuthenticationPrincipal SessionPrincipal principal) {
        return authService.getProfile(principal.userId());
    }

    @PutMapping("/users/me")
    public AuthDtos.UserProfile updateCurrentUser(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody AuthDtos.UpdateProfileRequest request) {
        return authService.updateProfile(principal.userId(), request);
    }

    @DeleteMapping("/users/me")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteCurrentUser(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody AuthDtos.DeleteAccountRequest request) {
        authService.deleteAccount(principal.userId(), request.password());
    }
}
