package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * One trip as an admin sees it, and the admin cancel. The trips list is
 * {@code GET /api/admin/trips} in AdminOperationsController, so there is no list route here.
 *
 * Every /api/admin/** route is limited to ROLE_ADMIN by SecurityConfig, the same rule that
 * protects the admin user list, so a signed-in non-admin gets 403 here.
 */
@RestController
@RequestMapping("/api/admin/trips")
public class AdminTripController {
    private final AdminTripService adminTrips;

    public AdminTripController(AdminTripService adminTrips) {
        this.adminTrips = adminTrips;
    }

    @GetMapping("/{tripId}")
    public AdminTripDtos.AdminTripDetail get(@PathVariable UUID tripId) {
        return adminTrips.get(tripId);
    }

    @PostMapping("/{tripId}/cancel")
    public TripDtos.TripDetail cancel(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @Valid @RequestBody TripDtos.CancelTripRequest request) {
        return adminTrips.cancel(principal.userId(), tripId, request.reason());
    }
}
