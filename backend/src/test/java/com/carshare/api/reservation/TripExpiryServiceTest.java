package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.vehicles.VehicleService;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** The expiry rule on a fixed clock, with a real TripService so the state machine really runs. */
@ExtendWith(MockitoExtension.class)
class TripExpiryServiceTest {
    private static final Instant NOW = Instant.parse("2026-11-12T12:00:00Z");

    @Mock private TripRepository trips;
    @Mock private TripEventRepository tripEvents;
    @Mock private UserRepository users;
    @Mock private ReservationService reservationService;
    @Mock private ReputationService reputationService;
    @Mock private VehicleService vehicleService;

    private TripExpiryService expiry;
    private AppUser driver;

    @BeforeEach
    void setUp() {
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        TripService tripService = new TripService(trips, tripEvents, users, reservationService,
                reputationService, vehicleService, clock);
        expiry = new TripExpiryService(trips, tripService, reservationService, clock);
        driver = new AppUser("Yacine Jomni", "+21612345678", "driver@carshare.tn", "hash", UserRole.DRIVER);
    }

    private Trip tripAt(Instant departure) {
        return new Trip(driver, UUID.randomUUID(), "Tunis Centre", 36.8, 10.18, "Sousse", 35.82, 10.63,
                departure, 3, new BigDecimal("10.00"), false, null, null, null, null);
    }

    @Test
    @DisplayName("a trip still scheduled 3 h after departure is cancelled as expired, seats released")
    void expiresAStaleTrip() {
        Trip stale = tripAt(NOW.minus(Duration.ofHours(3)));
        stale.recordConfirmedSeats(2);
        when(trips.findByStatusAndDepartureTimeBefore(eq(TripStatus.SCHEDULED), any()))
                .thenReturn(List.of(stale));

        int expired = expiry.expireStaleTrips();

        assertEquals(1, expired);
        assertEquals(TripStatus.CANCELLED, stale.getStatus());
        assertEquals(TripExpiryService.EXPIRED_REASON, stale.getCancelReason());
        assertEquals(stale.getSeatsTotal(), stale.getSeatsAvailable());
        assertEquals(0, stale.getConfirmedSeats());
    }

    @Test
    @DisplayName("the reason and the event name nobody as the actor, and reservations are closed")
    void recordsAnEventAndClosesReservations() {
        Trip stale = tripAt(NOW.minus(Duration.ofHours(5)));
        when(trips.findByStatusAndDepartureTimeBefore(eq(TripStatus.SCHEDULED), any()))
                .thenReturn(List.of(stale));

        expiry.expireStaleTrips();

        ArgumentCaptor<TripEvent> event = ArgumentCaptor.forClass(TripEvent.class);
        verify(tripEvents).save(event.capture());
        assertEquals(TripEventType.CANCELLED, event.getValue().getType());
        assertNull(event.getValue().getActorId());
        assertEquals(TripExpiryService.EXPIRED_REASON, event.getValue().getDetail());
        verify(reservationService).cancelAllForCancelledTrip(stale, null);
    }

    @Test
    @DisplayName("the cut-off is two hours before now, so a trip 1 h 30 late is left alone")
    void asksOnlyForTripsPastTheStartWindow() {
        when(trips.findByStatusAndDepartureTimeBefore(eq(TripStatus.SCHEDULED), any()))
                .thenReturn(List.of());

        int expired = expiry.expireStaleTrips();

        assertEquals(0, expired);
        ArgumentCaptor<Instant> cutoff = ArgumentCaptor.forClass(Instant.class);
        verify(trips).findByStatusAndDepartureTimeBefore(eq(TripStatus.SCHEDULED), cutoff.capture());
        assertEquals(NOW.minus(Duration.ofHours(2)), cutoff.getValue());
        verifyNoInteractions(tripEvents);
        verify(reservationService, never()).cancelAllForCancelledTrip(any(), any());
    }
}
