package com.carshare.api.admin;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** GET /api/admin/stats: every counter of the dashboard in one call. Admin only (SecurityConfig). */
@RestController
@RequestMapping("/api/admin/stats")
public class AdminStatsController {
    private final AdminStatsService stats;

    public AdminStatsController(AdminStatsService stats) {
        this.stats = stats;
    }

    @GetMapping
    public AdminDtos.Stats stats() {
        return stats.stats();
    }
}
