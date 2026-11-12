package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.when;

import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserTripStatsServiceTest {
    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private ReputationService reputation;

    private UserTripStatsService service;
    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new UserTripStatsService(trips, reservations, reputation);
    }

    @Test
    @DisplayName("a user with trips, ratings and no-shows gets every figure")
    void figuresForAnActiveUser() {
        when(trips.countByDriver_IdAndStatus(userId, TripStatus.COMPLETED)).thenReturn(5L);
        when(reservations.countByPassenger_IdAndStatus(userId, ReservationStatus.COMPLETED))
                .thenReturn(18L);
        when(reservations.countByPassenger_IdAndStatus(userId, ReservationStatus.NO_SHOW))
                .thenReturn(2L);
        when(reputation.forUser(userId))
                .thenReturn(new ReputationService.Reputation(4.6, 12L, 0.9));

        UserTripStatsDtos.UserTripStats stats = service.statsFor(userId);

        assertEquals(5, stats.tripsAsDriver());
        assertEquals(18, stats.tripsAsPassenger());
        assertEquals(23, stats.totalTrips());
        assertEquals(4.6, stats.rating());
        assertEquals(12, stats.ratingCount());
        assertEquals(2, stats.noShows());
        // 15 x (0.6 x 4.6/5 + 0.4 x 0.9) = 13.68, the same rounding the match score applies.
        assertEquals(MatchScorer.driverReliabilityPoints(4.6, 0.9), stats.reliability());
        assertEquals(14, stats.reliability());
    }

    @Test
    @DisplayName("a fresh user has zero counts, no rating and the newcomer reliability")
    void figuresForAFreshUser() {
        when(reputation.forUser(userId)).thenReturn(ReputationService.Reputation.NONE);

        UserTripStatsDtos.UserTripStats stats = service.statsFor(userId);

        assertEquals(0, stats.tripsAsDriver());
        assertEquals(0, stats.tripsAsPassenger());
        assertEquals(0, stats.totalTrips());
        assertNull(stats.rating());
        assertEquals(0, stats.ratingCount());
        assertEquals(0, stats.noShows());
        assertEquals(MatchScorer.NEW_DRIVER_RELIABILITY_POINTS, stats.reliability());
    }
}
