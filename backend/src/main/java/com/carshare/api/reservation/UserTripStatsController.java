package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The signed-in user's trip figures. The path sits under {@code /api/users/me}, next to the user
 * module's preferences, photo and sanctions routes, but is its own class so neither module's
 * controller changes.
 */
@RestController
@RequestMapping("/api/users/me")
public class UserTripStatsController {
    private final UserTripStatsService stats;

    public UserTripStatsController(UserTripStatsService stats) {
        this.stats = stats;
    }

    @GetMapping("/stats")
    public UserTripStatsDtos.UserTripStats myStats(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return stats.statsFor(principal.userId());
    }
}
