package com.carshare.api.admin;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.lostandfound.LostAndFoundReportRepository;
import com.carshare.api.lostandfound.LostAndFoundReportService;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.reservation.TripStatus;
import com.carshare.api.support.SupportTicketRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserAccountService;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserSanctionRepository;
import com.carshare.api.vehicles.VehicleRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;

/**
 * The status filter and the limit on {@code GET /api/admin/trips}, which already existed as an
 * unfiltered, unbounded list.
 */
@ExtendWith(MockitoExtension.class)
class AdminOperationsTripsListTest {
    @Mock private VehicleRepository vehicles;
    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private LostAndFoundReportRepository lostReports;
    @Mock private LostAndFoundReportService lostAndFound;
    @Mock private SupportTicketRepository tickets;
    @Mock private UserRepository users;
    @Mock private UserSanctionRepository sanctions;
    @Mock private UserAccountService accounts;

    private AdminOperationsService service;

    @BeforeEach
    void setUp() {
        service = new AdminOperationsService(vehicles, trips, reservations, lostReports,
                lostAndFound, tickets, users, sanctions, accounts);
    }

    @Test
    @DisplayName("no filter asks for every status, 100 rows")
    void defaultsAskForEveryStatus() {
        when(trips.findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class)))
                .thenReturn(List.of());

        assertTrue(service.trips(null, 100).isEmpty());

        ArgumentCaptor<Set<TripStatus>> statuses = statusCaptor();
        ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
        verify(trips).findByStatusInOrderByDepartureTimeDesc(statuses.capture(), page.capture());
        assertEquals(EnumSet.allOf(TripStatus.class), statuses.getValue());
        assertEquals(100, page.getValue().getPageSize());
        assertEquals(0, page.getValue().getPageNumber());
    }

    @Test
    @DisplayName("a status keeps only that status, whatever its case")
    void statusFilterKeepsOneStatus() {
        when(trips.findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class)))
                .thenReturn(List.of());

        service.trips(" scheduled ", 10);

        ArgumentCaptor<Set<TripStatus>> statuses = statusCaptor();
        verify(trips).findByStatusInOrderByDepartureTimeDesc(statuses.capture(), any(Pageable.class));
        assertEquals(EnumSet.of(TripStatus.SCHEDULED), statuses.getValue());
    }

    @Test
    @DisplayName("\"all\" and a blank status mean every status")
    void allAndBlankMeanEveryStatus() {
        when(trips.findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class)))
                .thenReturn(List.of());

        service.trips("ALL", 5);
        service.trips("  ", 5);

        ArgumentCaptor<Set<TripStatus>> statuses = statusCaptor();
        verify(trips, org.mockito.Mockito.times(2))
                .findByStatusInOrderByDepartureTimeDesc(statuses.capture(), any(Pageable.class));
        assertEquals(EnumSet.allOf(TripStatus.class), statuses.getAllValues().get(0));
        assertEquals(EnumSet.allOf(TripStatus.class), statuses.getAllValues().get(1));
    }

    @Test
    @DisplayName("an unknown status is a 400 invalid_status and nothing is queried")
    void unknownStatusIsRejected() {
        ApiException error = assertThrows(ApiException.class, () -> service.trips("flying", 100));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_status", error.getCode());
        verify(trips, never()).findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class));
    }

    @Test
    @DisplayName("the limit is kept between 1 and 500")
    void limitIsClamped() {
        when(trips.findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class)))
                .thenReturn(List.of());

        service.trips(null, 0);
        service.trips(null, -7);
        service.trips(null, 100000);

        ArgumentCaptor<Pageable> page = ArgumentCaptor.forClass(Pageable.class);
        verify(trips, org.mockito.Mockito.times(3))
                .findByStatusInOrderByDepartureTimeDesc(anyCollection(), page.capture());
        assertEquals(1, page.getAllValues().get(0).getPageSize());
        assertEquals(1, page.getAllValues().get(1).getPageSize());
        assertEquals(500, page.getAllValues().get(2).getPageSize());
    }

    @Test
    @DisplayName("each row keeps the fields the admin screen already shows")
    void rowsKeepTheExistingFields() {
        AppUser driver = new AppUser("Ahmed Ben Salah", "+21612345678", "d@carshare.tn", "hash", UserRole.DRIVER);
        Trip trip = new Trip(driver, null, "Tunis Centre", 36.8065, 10.1815, "Sousse", 35.8256, 10.636,
                Instant.now().plus(2, ChronoUnit.HOURS), 3, new BigDecimal("8.00"), false, null, null,
                null, null);
        when(trips.findByStatusInOrderByDepartureTimeDesc(anyCollection(), any(Pageable.class)))
                .thenReturn(List.of(trip));

        List<AdminOperationsService.AdminTrip> rows = service.trips("scheduled", 100);

        assertEquals(1, rows.size());
        AdminOperationsService.AdminTrip row = rows.get(0);
        assertEquals(trip.getId(), row.id());
        assertEquals("Ahmed Ben Salah", row.driverName());
        assertEquals("Tunis Centre", row.origin());
        assertEquals("Sousse", row.destination());
        assertEquals("SCHEDULED", row.status());
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<Set<TripStatus>> statusCaptor() {
        return ArgumentCaptor.forClass((Class<Set<TripStatus>>) (Class<?>) Set.class);
    }
}
