package com.carshare.api.admin;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.carshare.api.lostandfound.LostAndFoundReport;
import com.carshare.api.lostandfound.LostAndFoundReportRepository;
import com.carshare.api.lostandfound.LostAndFoundReportService;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.support.SupportTicketRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserAccountService;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserSanctionRepository;
import com.carshare.api.vehicles.VehicleRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class AdminLostAndFoundRouteTest {
    @Test
    @DisplayName("the admin list returns the trip's route and date, not only its id")
    void rowsCarryTheRoute() {
        LostAndFoundReportRepository reports = mock(LostAndFoundReportRepository.class);
        AdminOperationsService service = new AdminOperationsService(mock(VehicleRepository.class),
                mock(TripRepository.class), mock(ReservationRepository.class), reports,
                mock(LostAndFoundReportService.class), mock(SupportTicketRepository.class),
                mock(UserRepository.class), mock(UserSanctionRepository.class), mock(UserAccountService.class));
        AppUser driver = new AppUser("Ahmed", "+21611111111", "a@carshare.tn", "hash", UserRole.DRIVER);
        AppUser reporter = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        Instant departure = Instant.parse("2026-11-14T08:00:00Z");
        Trip trip = new Trip(driver, null, "Ennasr, Ariana, Tunis", 36.8, 10.15, "Sousse, Tunisie", 35.8, 10.6,
                departure, 3, new BigDecimal("10.00"), false, null, null, null, null);
        when(reports.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(new LostAndFoundReport(
                trip, reporter, LostAndFoundReport.Type.LOST, "Phone", "Black phone")));

        LostAndFoundReportService.ReportView row = service.lostAndFound().get(0);

        assertEquals("Ennasr, Ariana, Tunis", row.originLabel());
        assertEquals("Sousse, Tunisie", row.destinationLabel());
        assertEquals(departure, row.departureTime());
        assertEquals("Mariem", row.reporterName());
        assertEquals(trip.getId(), row.tripId());
    }
}
