package com.carshare.api.users;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/users")
public class AdminUserController {
    private final AdminUserService adminUsers;

    public AdminUserController(AdminUserService adminUsers) {
        this.adminUsers = adminUsers;
    }

    @GetMapping
    public List<AuthDtos.AdminUser> listUsers() {
        return adminUsers.listUsers();
    }

    @PutMapping("/{userId}")
    public AuthDtos.AdminUser updateUser(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID userId, @Valid @RequestBody AuthDtos.AdminUpdateUserRequest request) {
        return adminUsers.updateUser(principal.userId(), userId, request);
    }

    @PutMapping("/{userId}/status")
    public AuthDtos.AdminUser updateStatus(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID userId, @Valid @RequestBody AuthDtos.AdminStatusRequest request) {
        return adminUsers.updateStatus(principal.userId(), userId, request);
    }

}
