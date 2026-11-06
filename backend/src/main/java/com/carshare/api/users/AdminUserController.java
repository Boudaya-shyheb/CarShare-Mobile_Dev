package com.carshare.api.users;

import com.carshare.api.auth.AuthDtos;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/users")
public class AdminUserController {
    private final UserRepository users;

    public AdminUserController(UserRepository users) {
        this.users = users;
    }

    @GetMapping
    public List<AuthDtos.AdminUser> listUsers() {
        return users.findAllByOrderByCreatedAtDesc().stream().map(AuthDtos.AdminUser::from).toList();
    }
}
