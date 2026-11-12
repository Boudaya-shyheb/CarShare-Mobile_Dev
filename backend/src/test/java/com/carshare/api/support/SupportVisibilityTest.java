package com.carshare.api.support;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.lenient;

import com.carshare.api.reservation.Reservation;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.ReservationStatus;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SupportVisibilityTest {
    @Mock private SupportTicketRepository tickets;
    @Mock private UserRepository users;
    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private TicketCategoryRepository categories;
    @Mock private TicketStatusHistoryRepository history;
    @Mock private TicketEvidenceRepository evidence;
    @Mock private TicketStatementRepository statements;
    @Mock private TicketDecisionRepository decisions;
    @Mock private TicketContestationRepository contestations;
    @Mock private SupportNotificationRepository notifications;
    @Mock private SupportEvidenceStorage evidenceStorage;
    @Mock private SupportTicket ticket;
    @Mock private AppUser opener;
    @Mock private AppUser passenger;
    @Mock private Trip trip;
    @Mock private Reservation reservation;

    private SupportService service;

    @BeforeEach
    void setUp() {
        service = new SupportService(tickets, users, trips, reservations, categories,
                history, evidence, statements, decisions, contestations, notifications,
                evidenceStorage);
    }

    @Test
    void ticketListUsesParticipantVisibility() {
        UUID userId = UUID.randomUUID();
        when(tickets.findVisibleToUser(eq(userId), any())).thenReturn(List.of());

        assertTrue(service.myTickets(userId).isEmpty());

        verify(tickets).findVisibleToUser(eq(userId), any());
    }

    @Test
    void tripDriverCanReadEvidenceFromLegacyTripTicket() {
        UUID driverId = UUID.randomUUID();
        UUID tripId = UUID.randomUUID();
        UUID ticketId = UUID.randomUUID();
        prepareLegacyTicket(ticketId, tripId);
        when(trips.findById(tripId)).thenReturn(Optional.of(trip));
        when(trip.isDrivenBy(driverId)).thenReturn(true);
        when(evidence.findByTicket_IdOrderByCreatedAtAsc(ticketId)).thenReturn(List.of());

        assertTrue(service.evidence(driverId, ticketId).isEmpty());
    }

    @Test
    void tripPassengerCanReadEvidenceFromLegacyTripTicket() {
        UUID passengerId = UUID.randomUUID();
        UUID tripId = UUID.randomUUID();
        UUID ticketId = UUID.randomUUID();
        prepareLegacyTicket(ticketId, tripId);
        when(trips.findById(tripId)).thenReturn(Optional.of(trip));
        when(trip.isDrivenBy(passengerId)).thenReturn(false);
        when(reservations.findByTrip_IdAndStatusIn(eq(tripId), any()))
                .thenReturn(List.of(reservation));
        when(reservation.getPassenger()).thenReturn(passenger);
        when(passenger.getId()).thenReturn(passengerId);
        when(evidence.findByTicket_IdOrderByCreatedAtAsc(ticketId)).thenReturn(List.of());

        assertTrue(service.evidence(passengerId, ticketId).isEmpty());
    }

    @Test
    void reservationPassengerCanReadTheSharedEvidence() {
        UUID passengerId = UUID.randomUUID();
        UUID reservationId = UUID.randomUUID();
        UUID tripId = UUID.randomUUID();
        UUID ticketId = UUID.randomUUID();
        prepareLegacyTicket(ticketId, tripId);
        when(ticket.getReservationId()).thenReturn(reservationId);
        when(reservations.findById(reservationId)).thenReturn(Optional.of(reservation));
        when(reservation.isHeldBy(passengerId)).thenReturn(true);
        when(evidence.findByTicket_IdOrderByCreatedAtAsc(ticketId)).thenReturn(List.of());

        assertTrue(service.evidence(passengerId, ticketId).isEmpty());
    }

    @Test
    void driverCanChooseTheExactPassengerAndReservationToReport() {
        UUID driverId = UUID.randomUUID();
        UUID tripId = UUID.randomUUID();
        UUID passengerId = UUID.randomUUID();
        UUID reservationId = UUID.randomUUID();
        when(trips.findById(tripId)).thenReturn(Optional.of(trip));
        when(trip.isDrivenBy(driverId)).thenReturn(true);
        when(reservations.findByTrip_IdAndStatusIn(eq(tripId), eq(Set.of(
                        ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED,
                        ReservationStatus.NO_SHOW, ReservationStatus.CANCELLED))))
                .thenReturn(List.of(reservation));
        when(reservation.getPassenger()).thenReturn(passenger);
        when(reservation.getId()).thenReturn(reservationId);
        when(passenger.getId()).thenReturn(passengerId);
        when(passenger.getFullName()).thenReturn("Test Passenger");

        List<SupportService.ReportTargetView> targets = service.reportTargets(driverId, tripId);

        assertEquals(1, targets.size());
        assertEquals(passengerId, targets.get(0).userId());
        assertEquals(reservationId, targets.get(0).reservationId());
        assertEquals("PASSENGER", targets.get(0).role());
    }

    @Test
    void unreadNotificationCountIsScopedToTheCurrentUser() {
        UUID userId = UUID.randomUUID();
        when(notifications.countByUser_IdAndReadAtIsNull(userId)).thenReturn(3L);

        assertEquals(3L, service.unreadCount(userId).count());

        verify(notifications).countByUser_IdAndReadAtIsNull(userId);
    }

    private void prepareLegacyTicket(UUID ticketId, UUID tripId) {
        when(tickets.findDetailedById(ticketId)).thenReturn(Optional.of(ticket));
        when(ticket.getUser()).thenReturn(opener);
        when(opener.getId()).thenReturn(UUID.randomUUID());
        when(ticket.getReportedUser()).thenReturn(null);
        lenient().when(ticket.getTripId()).thenReturn(tripId);
    }
}
