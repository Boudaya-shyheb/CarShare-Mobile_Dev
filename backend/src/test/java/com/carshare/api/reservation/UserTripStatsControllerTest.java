package com.carshare.api.reservation;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.carshare.api.auth.AuthSession;
import com.carshare.api.auth.AuthSessionRepository;
import com.carshare.api.common.ApiExceptionHandler;
import com.carshare.api.security.SecurityConfig;
import com.carshare.api.security.TokenUtil;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * {@code GET /api/users/me/stats} behind the real security rules: the answer is about the user
 * the token belongs to, and a caller with no valid token never reaches the service.
 */
@WebMvcTest(controllers = UserTripStatsController.class)
@Import({SecurityConfig.class, ApiExceptionHandler.class})
@TestPropertySource(properties = "carshare.cors.allowed-origins=http://localhost:3000")
class UserTripStatsControllerTest {
    @Autowired private MockMvc mvc;

    @MockitoBean private UserTripStatsService stats;
    @MockitoBean private AuthSessionRepository sessions;

    @Test
    @DisplayName("a signed-in user gets their own figures, looked up by the id in the token")
    void ownFigures() throws Exception {
        AppUser user = new AppUser("Ines Trabelsi", "+21698765432", "ines@carshare.tn", "hash",
                UserRole.PASSENGER);
        AuthSession session = new AuthSession(user, TokenUtil.sha256("ines-token"),
                Instant.now().plus(1, ChronoUnit.HOURS));
        when(sessions.findByTokenHashAndExpiresAtAfter(eq(TokenUtil.sha256("ines-token")),
                any(Instant.class))).thenReturn(Optional.of(session));
        when(stats.statsFor(user.getId())).thenReturn(
                new UserTripStatsDtos.UserTripStats(5, 18, 23, 4.6, 12, 2, 14));

        mvc.perform(get("/api/users/me/stats").header("Authorization", "Bearer ines-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tripsAsDriver").value(5))
                .andExpect(jsonPath("$.tripsAsPassenger").value(18))
                .andExpect(jsonPath("$.totalTrips").value(23))
                .andExpect(jsonPath("$.rating").value(4.6))
                .andExpect(jsonPath("$.ratingCount").value(12))
                .andExpect(jsonPath("$.noShows").value(2))
                .andExpect(jsonPath("$.reliability").value(14));
    }

    @Test
    @DisplayName("a user nobody has rated gets a null rating, not a zero")
    void nullRating() throws Exception {
        AppUser user = new AppUser("New User", "+21611111111", "new@carshare.tn", "hash",
                UserRole.DRIVER);
        AuthSession session = new AuthSession(user, TokenUtil.sha256("new-token"),
                Instant.now().plus(1, ChronoUnit.HOURS));
        when(sessions.findByTokenHashAndExpiresAtAfter(eq(TokenUtil.sha256("new-token")),
                any(Instant.class))).thenReturn(Optional.of(session));
        when(stats.statsFor(user.getId())).thenReturn(
                new UserTripStatsDtos.UserTripStats(0, 0, 0, null, 0, 0, 10));

        mvc.perform(get("/api/users/me/stats").header("Authorization", "Bearer new-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalTrips").value(0))
                .andExpect(jsonPath("$.rating").doesNotExist())
                .andExpect(jsonPath("$.ratingCount").value(0));
    }

    @Test
    @DisplayName("no token is refused (403, as for every authenticated route) and nothing is read")
    void noToken() throws Exception {
        mvc.perform(get("/api/users/me/stats")).andExpect(status().isForbidden());

        verifyNoInteractions(stats);
    }

    @Test
    @DisplayName("an unknown or expired token is refused too")
    void unknownToken() throws Exception {
        when(sessions.findByTokenHashAndExpiresAtAfter(any(), any())).thenReturn(Optional.empty());

        mvc.perform(get("/api/users/me/stats").header("Authorization", "Bearer nope"))
                .andExpect(status().isForbidden());

        verifyNoInteractions(stats);
    }
}
