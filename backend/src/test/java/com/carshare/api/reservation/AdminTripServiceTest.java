package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
class AdminTripServiceTest {
    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private TripEventRepository tripEvents;
    @Mock private TripService tripService;

    private AdminTripService service;
    private AppUser driver;
    private AppUser passenger;

    @BeforeEach
    void setUp() {
        service = new AdminTripService(trips, reservations, tripEvents, tripService);
        driver = new AppUser("Yacine Jomni", "+21612345678", "driver@carshare.tn", "hash", UserRole.DRIVER);
        passenger = new AppUser("Ines Trabelsi", "+21698765432", "p@carshare.tn", "hash", UserRole.PASSENGER);
    }

    // --- GET /api/admin/trips/{id} ----------------------------------------------------------

    @Test
    @DisplayName("the detail has the trip, its passengers by name and its events in order")
    void detailHasTripPassengersAndEvents() {
        Trip trip = trip();
        Reservation booking = new Reservation(trip, passenger, 2, "1234");
        TripEvent published = new TripEvent(trip, TripEventType.PUBLISHED, driver.getId(), null, null, null);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdOrderByCreatedAtAsc(trip.getId())).thenReturn(List.of(booking));
        when(tripEvents.findByTrip_IdOrderByCreatedAtAsc(trip.getId())).thenReturn(List.of(published));

        AdminTripDtos.AdminTripDetail detail = service.get(trip.getId());

        assertEquals(trip.getId(), detail.trip().id());
        assertEquals("Yacine Jomni", detail.trip().driverName());
        assertEquals(1, detail.reservations().size());
        assertEquals("Ines Trabelsi", detail.reservations().get(0).passengerName());
        assertEquals(2, detail.reservations().get(0).seats());
        assertEquals(1, detail.events().size());
        assertEquals("PUBLISHED", detail.events().get(0).type());
    }

    @Test
    @DisplayName("an unknown trip is a 404 trip_not_found")
    void detailOfUnknownTripIs404() {
        UUID missing = UUID.randomUUID();
        when(trips.findById(missing)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class, () -> service.get(missing));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    // --- POST /api/admin/trips/{id}/cancel --------------------------------------------------

    @Test
    @DisplayName("cancelling goes through TripService, with the admin as the actor")
    void cancelDelegatesToTripService() {
        UUID adminId = UUID.randomUUID();
        UUID tripId = UUID.randomUUID();
        TripDtos.TripDetail cancelled = TripDtos.TripDetail.from(trip());
        when(tripService.cancelAsAdmin(adminId, tripId, "Fraud suspected")).thenReturn(cancelled);

        assertEquals(cancelled, service.cancel(adminId, tripId, "Fraud suspected"));

        verify(tripService).cancelAsAdmin(adminId, tripId, "Fraud suspected");
    }

    // --- the dashboard figures --------------------------------------------------------------

    @Test
    @DisplayName("the counters: total, in progress, completed, cancelled, reservations")
    void countersCoverEveryFigure() {
        when(trips.count()).thenReturn(12L);
        when(trips.countByStatusIn(anyCollection())).thenReturn(2L);
        when(trips.countByStatus(TripStatus.COMPLETED)).thenReturn(7L);
        when(trips.countByStatus(TripStatus.CANCELLED)).thenReturn(1L);
        when(reservations.count()).thenReturn(20L);

        AdminTripDtos.TripCounts counts = service.counts();

        assertEquals(new AdminTripDtos.TripCounts(12, 2, 7, 1, 20), counts);
        ArgumentCaptor<Set<TripStatus>> inProgress = statusCaptor();
        verify(trips).countByStatusIn(inProgress.capture());
        assertEquals(EnumSet.of(TripStatus.DRIVER_EN_ROUTE, TripStatus.DRIVER_ARRIVED,
                TripStatus.PICKED_UP, TripStatus.IN_PROGRESS), inProgress.getValue());
    }

    // --- helpers ----------------------------------------------------------------------------

    private Trip trip() {
        return new Trip(driver, null, "Tunis Centre", 36.8065, 10.1815, "Sousse", 35.8256, 10.6360,
                Instant.now().plus(3, ChronoUnit.HOURS), 3, new BigDecimal("12.50"), false, null,
                null, null, null);
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<Set<TripStatus>> statusCaptor() {
        return ArgumentCaptor.forClass((Class<Set<TripStatus>>) (Class<?>) Set.class);
    }
}
