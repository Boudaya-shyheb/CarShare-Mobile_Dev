package com.carshare.api.admin;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.carshare.api.auth.AuthSession;
import com.carshare.api.auth.AuthSessionRepository;
import com.carshare.api.common.ApiExceptionHandler;
import com.carshare.api.reservation.AdminTripController;
import com.carshare.api.reservation.AdminTripDtos;
import com.carshare.api.reservation.AdminTripService;
import com.carshare.api.security.SecurityConfig;
import com.carshare.api.security.TokenUtil;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import com.carshare.api.vehicles.VehicleService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * The admin routes behind the real security rules: SecurityConfig, the real token filter and the
 * real error handler. Only the services and the session lookup are replaced. Whoever the token
 * belongs to decides the answer, exactly as in the running API: an admin gets in, any other
 * signed-in user or anonymous caller gets 403, and the service is never reached.
 *
 * Covers the trips list (the operations controller), the trip detail, the admin cancel and the
 * dashboard counters.
 */
@WebMvcTest(controllers = {AdminTripController.class, AdminStatsController.class,
        AdminOperationsController.class})
@Import({SecurityConfig.class, ApiExceptionHandler.class})
@TestPropertySource(properties = "carshare.cors.allowed-origins=http://localhost:3000")
class AdminEndpointsSecurityTest {
    private static final String CANCEL_BODY = "{\"reason\":\"Reported by two riders\"}";

    @Autowired private MockMvc mvc;

    @MockitoBean private AdminTripService adminTrips;
    @MockitoBean private AdminStatsService adminStats;
    @MockitoBean private AdminOperationsService adminOperations;
    @MockitoBean private VehicleService vehicleService; // the operations controller needs it
    @MockitoBean private AuthSessionRepository sessions;

    private final UUID tripId = UUID.randomUUID();

    // --- an admin gets in -------------------------------------------------------------------

    @Test
    @DisplayName("GET /api/admin/trips answers an admin and passes the status and the limit on")
    void adminListsTrips() throws Exception {
        signInAs(UserRole.ADMIN, "admin-token");
        when(adminOperations.trips("scheduled", 25)).thenReturn(List.of());

        mvc.perform(get("/api/admin/trips").param("status", "scheduled").param("limit", "25")
                        .header("Authorization", "Bearer admin-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray());

        verify(adminOperations).trips("scheduled", 25);
    }

    @Test
    @DisplayName("GET /api/admin/trips with no parameters means every status and a limit of 100")
    void listDefaults() throws Exception {
        signInAs(UserRole.ADMIN, "admin-token");
        when(adminOperations.trips(null, 100)).thenReturn(List.of());

        mvc.perform(get("/api/admin/trips").header("Authorization", "Bearer admin-token"))
                .andExpect(status().isOk());

        verify(adminOperations).trips(null, 100);
    }

    @Test
    @DisplayName("GET /api/admin/trips/{id} answers an admin")
    void adminOpensATrip() throws Exception {
        signInAs(UserRole.ADMIN, "admin-token");
        when(adminTrips.get(tripId))
                .thenReturn(new AdminTripDtos.AdminTripDetail(null, List.of(), List.of()));

        mvc.perform(get("/api/admin/trips/" + tripId).header("Authorization", "Bearer admin-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reservations").isArray())
                .andExpect(jsonPath("$.events").isArray());
    }

    @Test
    @DisplayName("POST /api/admin/trips/{id}/cancel runs the cancel with the admin's own id")
    void adminCancelsATrip() throws Exception {
        AppUser admin = signInAs(UserRole.ADMIN, "admin-token");

        mvc.perform(post("/api/admin/trips/" + tripId + "/cancel")
                        .header("Authorization", "Bearer admin-token")
                        .contentType(MediaType.APPLICATION_JSON).content(CANCEL_BODY))
                .andExpect(status().isOk());

        verify(adminTrips).cancel(admin.getId(), tripId, "Reported by two riders");
    }

    @Test
    @DisplayName("a cancel without a reason is a 400 validation_error")
    void cancelNeedsAReason() throws Exception {
        signInAs(UserRole.ADMIN, "admin-token");

        mvc.perform(post("/api/admin/trips/" + tripId + "/cancel")
                        .header("Authorization", "Bearer admin-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"  \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_error"));

        verifyNoInteractions(adminTrips);
    }

    @Test
    @DisplayName("GET /api/admin/stats answers an admin with every counter")
    void adminReadsStats() throws Exception {
        signInAs(UserRole.ADMIN, "admin-token");
        when(adminStats.stats()).thenReturn(new AdminDtos.Stats(5, 12, 2, 7, 1, 20, 3));

        mvc.perform(get("/api/admin/stats").header("Authorization", "Bearer admin-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.users").value(5))
                .andExpect(jsonPath("$.tripsTotal").value(12))
                .andExpect(jsonPath("$.tripsInProgress").value(2))
                .andExpect(jsonPath("$.tripsCompleted").value(7))
                .andExpect(jsonPath("$.tripsCancelled").value(1))
                .andExpect(jsonPath("$.reservations").value(20))
                .andExpect(jsonPath("$.lostAndFoundReports").value(3));
    }

    // --- everybody else gets 403 ------------------------------------------------------------

    @Test
    @DisplayName("a passenger gets 403 on every one of these admin routes")
    void passengerIsForbidden() throws Exception {
        signInAs(UserRole.PASSENGER, "passenger-token");
        assertAllForbidden("Bearer passenger-token");
    }

    @Test
    @DisplayName("a driver gets 403 on every one of these admin routes")
    void driverIsForbidden() throws Exception {
        signInAs(UserRole.DRIVER, "driver-token");
        assertAllForbidden("Bearer driver-token");
    }

    @Test
    @DisplayName("a caller with no token gets 403 on every one of these admin routes")
    void anonymousIsForbidden() throws Exception {
        assertAllForbidden(null);
    }

    @Test
    @DisplayName("an unknown or expired token gets 403 on every one of these admin routes")
    void unknownTokenIsForbidden() throws Exception {
        when(sessions.findByTokenHashAndExpiresAtAfter(any(), any())).thenReturn(Optional.empty());
        assertAllForbidden("Bearer not-a-real-token");
    }

    // --- helpers ----------------------------------------------------------------------------

    private void assertAllForbidden(String authorization) throws Exception {
        var list = get("/api/admin/trips").param("status", "scheduled");
        var detail = get("/api/admin/trips/" + tripId);
        var cancel = post("/api/admin/trips/" + tripId + "/cancel")
                .contentType(MediaType.APPLICATION_JSON).content(CANCEL_BODY);
        var stats = get("/api/admin/stats");
        if (authorization != null) {
            list.header("Authorization", authorization);
            detail.header("Authorization", authorization);
            cancel.header("Authorization", authorization);
            stats.header("Authorization", authorization);
        }

        mvc.perform(list).andExpect(status().isForbidden());
        mvc.perform(detail).andExpect(status().isForbidden());
        mvc.perform(cancel).andExpect(status().isForbidden());
        mvc.perform(stats).andExpect(status().isForbidden());

        // The request never got as far as the services.
        verifyNoInteractions(adminTrips, adminStats, adminOperations);
    }

    /** Makes [token] a live session of a new user with [role]; the filter reads the role from it. */
    private AppUser signInAs(UserRole role, String token) {
        AppUser user = new AppUser("Test " + role.value(), "+21611111111",
                role.value() + "@carshare.tn", "hash", role);
        AuthSession session = new AuthSession(user, TokenUtil.sha256(token),
                Instant.now().plus(1, ChronoUnit.HOURS));
        when(sessions.findByTokenHashAndExpiresAtAfter(eq(TokenUtil.sha256(token)), any(Instant.class)))
                .thenReturn(Optional.of(session));
        return user;
    }
}
