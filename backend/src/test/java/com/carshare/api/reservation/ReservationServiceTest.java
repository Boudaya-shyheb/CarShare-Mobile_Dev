package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import java.lang.reflect.RecordComponent;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
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
class ReservationServiceTest {
    private static final Instant NOW = Instant.parse("2026-11-20T06:00:00Z");
    private static final Instant DEPARTURE = NOW.plus(5, ChronoUnit.HOURS);

    @Mock private ReservationRepository reservations;
    @Mock private TripRepository trips;
    @Mock private TripEventRepository tripEvents;
    @Mock private UserRepository users;
    @Mock private ReputationService reputationService;

    private ReservationService service;
    private AppUser driver;
    private AppUser passenger;
    private UUID passengerId;

    @BeforeEach
    void setUp() {
        service = new ReservationService(reservations, trips, tripEvents, users,
                reputationService, Clock.fixed(NOW, ZoneOffset.UTC));
        // A mock answers null by default, which would NPE wherever a reputation is read.
        lenient().when(reputationService.forUser(any()))
                .thenReturn(ReputationService.Reputation.NONE);
        lenient().when(reputationService.ratingsFor(any())).thenReturn(java.util.Map.of());
        driver = new AppUser("Ahmed Driver", "+21611111111", "ahmed@carshare.tn", "hash",
                UserRole.DRIVER);
        passenger = new AppUser("Mouna Passenger", "+21622222222", "mouna@carshare.tn", "hash",
                UserRole.PASSENGER);
        passengerId = passenger.getId();
    }

    // --- booking ------------------------------------------------------------------------------

    @Test
    @DisplayName("instant booking confirms the reservation straight away")
    void instantBookingConfirmsImmediately() {
        Trip trip = givenTrip(4, true);
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();
        when(trips.addConfirmedSeats(trip.getId(), 2)).thenReturn(1);

        ReservationDtos.ReservationDetail result = service.book(passengerId, trip.getId(), book(2));

        assertEquals(ReservationStatus.CONFIRMED.name(), result.status());
        assertEquals(2, result.seats());
        // The write response is built before the flush, so createdAt has to be stamped by
        // the constructor or it reaches the client as null.
        assertNotNull(result.createdAt());
        verify(trips).holdSeats(trip.getId(), 2);
        verify(trips).addConfirmedSeats(trip.getId(), 2);
        assertEquals(TripEventType.RESERVATION_CONFIRMED, savedEvent().getType());
    }

    @Test
    @DisplayName("without instant booking the reservation waits for the driver")
    void withoutInstantBookingTheReservationIsPending() {
        Trip trip = givenTrip(4, false);
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();

        ReservationDtos.ReservationDetail result = service.book(passengerId, trip.getId(), book(1));

        assertEquals(ReservationStatus.PENDING.name(), result.status());
        verify(trips).holdSeats(trip.getId(), 1);
        verify(trips, never()).addConfirmedSeats(any(), anyInt());
        assertEquals(TripEventType.RESERVATION_REQUESTED, savedEvent().getType());
    }

    @Test
    @DisplayName("seats are held the moment they are requested, not when they are accepted")
    void holdsSeatsAtRequestTime() {
        Trip trip = givenTrip(4, false);
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();

        service.book(passengerId, trip.getId(), book(3));

        verify(trips).holdSeats(trip.getId(), 3);
    }

    @Test
    @DisplayName("losing the race for the last seat is a 409, and nothing is written")
    void refusesWhenTheSeatsWereJustTaken() {
        Trip trip = givenTrip(1, false);
        givenActivePassenger();
        givenNoOtherReservations();
        // The conditional UPDATE changed no row: another passenger got there first.
        when(trips.holdSeats(trip.getId(), 1)).thenReturn(0);

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(passengerId, trip.getId(), book(1)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("seats_unavailable", error.getCode());
        verify(reservations, never()).save(any());
        verifyNoInteractions(tripEvents);
    }

    @Test
    @DisplayName("two passengers chasing one seat: the second one is refused")
    void onlyOnePassengerGetsTheLastSeat() {
        Trip trip = givenTrip(1, true);
        AppUser second = new AppUser("Sami", "+21633333333", "sami@carshare.tn", "hash",
                UserRole.PASSENGER);
        when(users.findById(passengerId)).thenReturn(Optional.of(passenger));
        when(users.findById(second.getId())).thenReturn(Optional.of(second));
        givenNoOtherReservations();
        when(trips.addConfirmedSeats(trip.getId(), 1)).thenReturn(1);
        // The first call wins the row, the second changes nothing.
        when(trips.holdSeats(trip.getId(), 1)).thenReturn(1, 0);

        ReservationDtos.ReservationDetail winner =
                service.book(passengerId, trip.getId(), book(1));
        ApiException loser = assertThrows(ApiException.class,
                () -> service.book(second.getId(), trip.getId(), book(1)));

        assertEquals(ReservationStatus.CONFIRMED.name(), winner.status());
        assertEquals("seats_unavailable", loser.getCode());
        verify(reservations, org.mockito.Mockito.times(1)).save(any());
    }

    @Test
    @DisplayName("a driver cannot book a seat on their own trip")
    void refusesOwnTrip() {
        Trip trip = givenTrip(4, false);
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(driver.getId(), trip.getId(), book(1)));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("own_trip", error.getCode());
        verify(trips, never()).holdSeats(any(), anyInt());
    }

    @Test
    @DisplayName("a trip that has already set off takes no more reservations")
    void refusesTripThatIsUnderway() {
        Trip trip = givenTrip(4, false);
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        givenActivePassenger();

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(passengerId, trip.getId(), book(1)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("trip_not_bookable", error.getCode());
        verify(trips, never()).holdSeats(any(), anyInt());
    }

    @Test
    @DisplayName("a trip whose departure has passed takes no more reservations")
    void refusesTripInThePast() {
        Trip trip = tripLeavingAt(NOW.minus(1, ChronoUnit.MINUTES), 4, false);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        givenActivePassenger();

        assertEquals("trip_not_bookable", assertThrows(ApiException.class,
                () -> service.book(passengerId, trip.getId(), book(1))).getCode());
    }

    @Test
    @DisplayName("a suspended or banned passenger cannot book")
    void refusesRestrictedPassenger() {
        for (UserStatus restricted : List.of(UserStatus.SUSPENDED, UserStatus.BANNED)) {
            passenger.updateAccountStatus(restricted, null);
            when(users.findById(passengerId)).thenReturn(Optional.of(passenger));

            ApiException error = assertThrows(ApiException.class,
                    () -> service.book(passengerId, UUID.randomUUID(), book(1)));

            assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
            assertEquals(restricted == UserStatus.BANNED ? "account_banned" : "account_suspended",
                    error.getCode());
        }
        verify(trips, never()).holdSeats(any(), anyInt());
    }

    @Test
    @DisplayName("a warned passenger can still book")
    void allowsWarnedPassenger() {
        Trip trip = givenTrip(4, false);
        passenger.updateAccountStatus(UserStatus.WARNING, NOW.plus(1, ChronoUnit.DAYS));
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();

        assertEquals(ReservationStatus.PENDING.name(),
                service.book(passengerId, trip.getId(), book(1)).status());
    }

    @Test
    @DisplayName("an account that no longer exists cannot book")
    void refusesUnknownAccount() {
        when(users.findById(passengerId)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(passengerId, UUID.randomUUID(), book(1)));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals("account_not_found", error.getCode());
    }

    @Test
    @DisplayName("booking a trip that does not exist is a 404")
    void refusesUnknownTrip() {
        UUID tripId = UUID.randomUUID();
        givenActivePassenger();
        when(trips.findById(tripId)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(passengerId, tripId, book(1)));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("every reservation is born with a four-digit pickup code")
    void generatesAPickupCode() {
        Trip trip = givenTrip(4, false);
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();

        service.book(passengerId, trip.getId(), book(1));

        assertTrue(PickupCode.isWellFormed(savedReservation().getPickupCode()));
    }

    // --- the overlap rule ---------------------------------------------------------------------

    @Test
    @DisplayName("a reservation on a trip at the same time blocks the booking")
    void refusesOverlappingReservation() {
        Trip wanted = givenTrip(4, false);
        givenActivePassenger();
        givenHeldReservationOn(tripLeavingAt(DEPARTURE, 4, false));

        ApiException error = assertThrows(ApiException.class,
                () -> service.book(passengerId, wanted.getId(), book(1)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("overlapping_reservation", error.getCode());
        verify(trips, never()).holdSeats(any(), anyInt());
    }

    @Test
    @DisplayName("an overlap of a single minute still blocks the booking")
    void refusesOverlapByOneMinute() {
        Trip wanted = givenTrip(4, false); // leaves 11:00, arrives 13:00
        givenActivePassenger();
        // Arrives 11:01, one minute after the wanted trip leaves.
        givenHeldReservationOn(tripLeavingAt(DEPARTURE.minus(119, ChronoUnit.MINUTES), 4, false));

        assertEquals("overlapping_reservation", assertThrows(ApiException.class,
                () -> service.book(passengerId, wanted.getId(), book(1))).getCode());
    }

    @Test
    @DisplayName("a trip arriving exactly as the next one leaves is not an overlap")
    void allowsBackToBackTrips() {
        Trip wanted = givenTrip(4, false); // leaves 11:00
        givenActivePassenger();
        // Arrives at exactly 11:00.
        givenHeldReservationOn(tripLeavingAt(DEPARTURE.minus(2, ChronoUnit.HOURS), 4, false));
        givenSeatsCanBeHeld();

        assertEquals(ReservationStatus.PENDING.name(),
                service.book(passengerId, wanted.getId(), book(1)).status());
    }

    @Test
    @DisplayName("a known route duration frees the diary earlier than the two-hour default")
    void usesRouteDurationForTheWindow() {
        Trip wanted = givenTrip(4, false); // leaves 11:00
        givenActivePassenger();
        // Leaves 10:00 and is known to take 30 minutes, so it is done well before 11:00.
        Trip quick = new Trip(driver, null, "A", 36.8, 10.18, "B", 35.82, 10.63,
                DEPARTURE.minus(1, ChronoUnit.HOURS), 4, new BigDecimal("8.00"), false, null,
                null, 1_800, null);
        givenHeldReservationOn(quick);
        givenSeatsCanBeHeld();

        assertEquals(ReservationStatus.PENDING.name(),
                service.book(passengerId, wanted.getId(), book(1)).status());
    }

    @Test
    @DisplayName("booking the same trip twice is caught by the overlap rule")
    void refusesBookingTheSameTripTwice() {
        Trip trip = givenTrip(4, false);
        givenActivePassenger();
        givenHeldReservationOn(trip);

        assertEquals("overlapping_reservation", assertThrows(ApiException.class,
                () -> service.book(passengerId, trip.getId(), book(1))).getCode());
    }

    @Test
    @DisplayName("only pending and confirmed reservations are checked for an overlap")
    void onlyActiveReservationsBlockABooking() {
        Trip trip = givenTrip(4, false);
        givenActivePassenger();
        givenNoOtherReservations();
        givenSeatsCanBeHeld();

        service.book(passengerId, trip.getId(), book(1));

        ArgumentCaptor<Set<ReservationStatus>> statuses = captureStatuses();
        verify(reservations).findByPassenger_IdAndStatusIn(eq(passengerId), statuses.capture());
        assertEquals(Set.of(ReservationStatus.PENDING, ReservationStatus.CONFIRMED),
                statuses.getValue());
    }

    // --- the driver answering -----------------------------------------------------------------

    @Test
    @DisplayName("accepting a request confirms it and locks the trip")
    void acceptConfirmsAndCountsTheSeats() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 2);
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));
        when(trips.addConfirmedSeats(trip.getId(), 2)).thenReturn(1);

        ReservationDtos.PassengerView result = service.accept(driver.getId(), reservation.getId());

        assertEquals(ReservationStatus.CONFIRMED.name(), result.status());
        assertEquals(NOW, reservation.getDecidedAt());
        verify(trips).addConfirmedSeats(trip.getId(), 2);
        verify(trips, never()).releaseSeats(any(), anyInt());
        assertEquals(TripEventType.RESERVATION_CONFIRMED, savedEvent().getType());
    }

    @Test
    @DisplayName("refusing a request gives the seats back")
    void refuseReleasesTheSeats() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 2);
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));

        ReservationDtos.PassengerView result = service.refuse(driver.getId(), reservation.getId());

        assertEquals(ReservationStatus.REFUSED.name(), result.status());
        verify(trips).releaseSeats(trip.getId(), 2);
        // The seats were never confirmed, so the confirmed count must not move.
        verify(trips, never()).releaseConfirmedSeats(any(), anyInt());
        assertEquals(TripEventType.RESERVATION_REFUSED, savedEvent().getType());
    }

    @Test
    @DisplayName("a reservation can only be answered while it is pending")
    void refusesToAnswerTwice() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 1);
        reservation.confirm(NOW);
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));

        ApiException error = assertThrows(ApiException.class,
                () -> service.accept(driver.getId(), reservation.getId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_reservation_state", error.getCode());
    }

    @Test
    @DisplayName("another driver answering a request gets a 404, not a hint that it exists")
    void refusesAnotherDriver() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 1);
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));

        ApiException error = assertThrows(ApiException.class,
                () -> service.accept(UUID.randomUUID(), reservation.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
        verify(trips, never()).addConfirmedSeats(any(), anyInt());
    }

    @Test
    @DisplayName("a request on a cancelled trip cannot be accepted")
    void refusesToAcceptOntoACancelledTrip() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 1);
        trip.cancel("Car broke down");
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));

        assertEquals("trip_not_bookable", assertThrows(ApiException.class,
                () -> service.accept(driver.getId(), reservation.getId())).getCode());
    }

    @Test
    @DisplayName("answering a reservation that does not exist is a 404")
    void refusesUnknownReservation() {
        UUID reservationId = UUID.randomUUID();
        when(reservations.findById(reservationId)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.refuse(driver.getId(), reservationId));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("reservation_not_found", error.getCode());
    }

    // --- the passenger cancelling -------------------------------------------------------------

    @Test
    @DisplayName("cancelling a pending reservation gives the held seats back")
    void cancelPendingReleasesHeldSeats() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 2);
        givenOwnReservation(reservation);

        ReservationDtos.ReservationDetail result =
                service.cancel(passengerId, reservation.getId(), "Plans changed");

        assertEquals(ReservationStatus.CANCELLED.name(), result.status());
        assertEquals("Plans changed", reservation.getCancelReason());
        assertEquals(NOW, reservation.getCancelledAt());
        verify(trips).releaseSeats(trip.getId(), 2);
        verify(trips, never()).releaseConfirmedSeats(any(), anyInt());
    }

    @Test
    @DisplayName("cancelling a confirmed reservation also unlocks the trip")
    void cancelConfirmedReleasesConfirmedSeats() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation reservation = pendingReservation(trip, 2);
        reservation.confirm(NOW.minus(1, ChronoUnit.HOURS));
        givenOwnReservation(reservation);

        service.cancel(passengerId, reservation.getId(), "Plans changed");

        verify(trips).releaseSeats(trip.getId(), 2);
        verify(trips).releaseConfirmedSeats(trip.getId(), 2);
    }

    @Test
    @DisplayName("cancelling well before departure is free")
    void cancellingEarlyIsFree() {
        // NOW is five hours before departure.
        Reservation reservation = pendingReservation(tripNotLookedUpById(4, false), 1);
        givenOwnReservation(reservation);

        ReservationDtos.ReservationDetail result =
                service.cancel(passengerId, reservation.getId(), "Plans changed");

        assertFalse(result.lateCancellation());
        assertFalse(reservation.isLateCancellation());
    }

    @Test
    @DisplayName("cancelling exactly two hours before departure is still free")
    void cancellingAtTheBoundaryIsFree() {
        Trip trip = tripLeavingAt(NOW.plus(2, ChronoUnit.HOURS), 4, false);
        Reservation reservation = pendingReservation(trip, 1);
        givenOwnReservation(reservation);

        assertFalse(service.cancel(passengerId, reservation.getId(), "Plans changed")
                .lateCancellation());
    }

    @Test
    @DisplayName("one minute inside the two hours is a late cancellation")
    void cancellingInsideTheBoundaryIsLate() {
        Trip trip = tripLeavingAt(NOW.plus(119, ChronoUnit.MINUTES), 4, false);
        Reservation reservation = pendingReservation(trip, 1);
        givenOwnReservation(reservation);

        ReservationDtos.ReservationDetail result =
                service.cancel(passengerId, reservation.getId(), "Plans changed");

        assertTrue(result.lateCancellation());
        assertTrue(reservation.isLateCancellation());
        // The seats still come back; only the mark differs.
        verify(trips).releaseSeats(trip.getId(), 1);
    }

    @Test
    @DisplayName("the free-cancellation window is two hours")
    void freeCancellationWindowIsTwoHours() {
        assertEquals(Duration.ofHours(2), ReservationService.FREE_CANCELLATION_WINDOW);
    }

    @Test
    @DisplayName("cancelling without a reason is refused")
    void cancellingNeedsAReason() {
        for (String blank : Arrays.asList(null, "", "   ")) {
            ApiException error = assertThrows(ApiException.class,
                    () -> service.cancel(passengerId, UUID.randomUUID(), blank));

            assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
            assertEquals("cancel_reason_required", error.getCode());
        }
        verifyNoInteractions(reservations);
    }

    @Test
    @DisplayName("a reservation that is already closed cannot be cancelled")
    void cancellingTwiceIsRefused() {
        Reservation reservation = pendingReservation(tripNotLookedUpById(4, false), 1);
        reservation.cancel("Plans changed", false, NOW.minus(1, ChronoUnit.HOURS));
        givenOwnReservation(reservation);

        ApiException error = assertThrows(ApiException.class,
                () -> service.cancel(passengerId, reservation.getId(), "Again"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_reservation_state", error.getCode());
        verify(trips, never()).releaseSeats(any(), anyInt());
    }

    @Test
    @DisplayName("a passenger cannot cancel somebody else's reservation")
    void cannotCancelSomeoneElsesReservation() {
        UUID reservationId = UUID.randomUUID();
        when(reservations.findByIdAndPassenger_Id(reservationId, passengerId))
                .thenReturn(Optional.empty());

        assertEquals("reservation_not_found", assertThrows(ApiException.class,
                () -> service.cancel(passengerId, reservationId, "Plans changed")).getCode());
    }

    // --- the passenger's own list -------------------------------------------------------------

    @Test
    @DisplayName("the pickup code is shown only once the reservation is confirmed")
    void pickupCodeAppearsOnlyWhenConfirmed() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation pending = new Reservation(trip, passenger, 1, "1234");
        Reservation confirmed = new Reservation(trip, passenger, 1, "5678");
        confirmed.confirm(NOW);
        when(reservations.findByPassenger_IdOrderByCreatedAtDesc(passengerId))
                .thenReturn(List.of(pending, confirmed));

        List<ReservationDtos.ReservationDetail> result = service.listMine(passengerId, null);

        assertNull(result.get(0).pickupCode(), "a pending reservation must not show a code");
        assertEquals("5678", result.get(1).pickupCode());
    }

    @Test
    @DisplayName("upcoming, past and cancelled each read their own statuses")
    void scopesMapToStatusSets() {
        when(reservations.findByPassenger_IdAndStatusInOrderByCreatedAtDesc(eq(passengerId), any()))
                .thenReturn(List.of());

        service.listMine(passengerId, "upcoming");
        service.listMine(passengerId, "past");
        service.listMine(passengerId, "cancelled");

        ArgumentCaptor<Set<ReservationStatus>> statuses = captureStatuses();
        verify(reservations, org.mockito.Mockito.times(3))
                .findByPassenger_IdAndStatusInOrderByCreatedAtDesc(eq(passengerId),
                        statuses.capture());
        assertEquals(Set.of(ReservationStatus.PENDING, ReservationStatus.CONFIRMED),
                statuses.getAllValues().get(0));
        assertEquals(Set.of(ReservationStatus.COMPLETED, ReservationStatus.NO_SHOW),
                statuses.getAllValues().get(1));
        assertEquals(Set.of(ReservationStatus.CANCELLED, ReservationStatus.REFUSED),
                statuses.getAllValues().get(2));
    }

    @Test
    @DisplayName("no scope means every reservation")
    void noScopeReturnsEverything() {
        when(reservations.findByPassenger_IdOrderByCreatedAtDesc(passengerId))
                .thenReturn(List.of());

        assertTrue(service.listMine(passengerId, "  ").isEmpty());
        verify(reservations).findByPassenger_IdOrderByCreatedAtDesc(passengerId);
    }

    @Test
    @DisplayName("an unknown scope is refused")
    void unknownScopeIsRefused() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.listMine(passengerId, "refused"));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_reservation_scope", error.getCode());
    }

    // --- what the driver sees -----------------------------------------------------------------

    @Test
    @DisplayName("the driver sees who booked, with seats and status")
    void driverSeesPassengers() {
        Trip trip = givenTrip(4, false);
        Reservation reservation = pendingReservation(trip, 2);
        when(reservations.findByTrip_IdOrderByCreatedAtAsc(trip.getId()))
                .thenReturn(List.of(reservation));

        List<ReservationDtos.PassengerView> result =
                service.listForTrip(driver.getId(), trip.getId());

        assertEquals(1, result.size());
        assertEquals("Mouna Passenger", result.get(0).passengerName());
        assertEquals(2, result.get(0).seats());
        assertEquals(ReservationStatus.PENDING.name(), result.get(0).status());
    }

    @Test
    @DisplayName("another driver listing the passengers gets a 404")
    void otherDriversCannotSeePassengers() {
        Trip trip = givenTrip(4, false);

        ApiException error = assertThrows(ApiException.class,
                () -> service.listForTrip(UUID.randomUUID(), trip.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("the driver's record has no pickup code field at all")
    void driverRecordCannotCarryAPickupCode() {
        List<String> fields = Arrays.stream(ReservationDtos.PassengerView.class
                        .getRecordComponents()).map(RecordComponent::getName)
                .map(name -> name.toLowerCase(Locale.ROOT)).toList();

        assertFalse(fields.stream().anyMatch(name -> name.contains("code")), fields.toString());
    }

    // --- the driver cancelling the trip -------------------------------------------------------

    @Test
    @DisplayName("cancelling a trip closes every live reservation on it")
    void cancellingATripClosesItsReservations() {
        Trip trip = tripNotLookedUpById(4, false);
        Reservation pending = pendingReservation(trip, 1);
        Reservation confirmed = pendingReservation(trip, 2);
        confirmed.confirm(NOW.minus(1, ChronoUnit.HOURS));
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of(pending, confirmed));

        service.cancelAllForCancelledTrip(trip, driver.getId());

        for (Reservation closed : List.of(pending, confirmed)) {
            assertEquals(ReservationStatus.CANCELLED, closed.getStatus());
            assertEquals("trip_cancelled", closed.getCancelReason());
            // The driver called it off, so this is not held against the passenger.
            assertFalse(closed.isLateCancellation());
            assertEquals(NOW, closed.getCancelledAt());
        }
        // Trip.cancel already returned every seat in one go.
        verify(trips, never()).releaseSeats(any(), anyInt());
        verify(trips, never()).releaseConfirmedSeats(any(), anyInt());
        verify(tripEvents, org.mockito.Mockito.times(2)).save(any());
    }

    @Test
    @DisplayName("cancelling a trip with no reservations does nothing")
    void cancellingAnEmptyTripIsHarmless() {
        Trip trip = tripNotLookedUpById(4, false);
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of());

        service.cancelAllForCancelledTrip(trip, driver.getId());

        verifyNoInteractions(tripEvents);
    }

    // --- the auto-refuse job ------------------------------------------------------------------

    @Test
    @DisplayName("the job looks back two hours and ahead thirty minutes from the clock")
    void autoRefuseUsesTheRightWindows() {
        when(reservations.findAutoRefusable(any(), any(), any())).thenReturn(List.of());

        assertEquals(0, service.autoRefusePending());

        verify(reservations).findAutoRefusable(ReservationStatus.PENDING,
                NOW.minus(2, ChronoUnit.HOURS), NOW.plus(30, ChronoUnit.MINUTES));
    }

    @Test
    @DisplayName("the job refuses what it finds and gives the seats back")
    void autoRefuseRefusesAndReleases() {
        Trip unanswered = tripNotLookedUpById(4, false);
        Trip leavingSoon = tripLeavingAt(NOW.plus(10, ChronoUnit.MINUTES), 4, false);
        Reservation first = pendingReservation(unanswered, 1);
        Reservation second = pendingReservation(leavingSoon, 3);
        when(reservations.findAutoRefusable(any(), any(), any()))
                .thenReturn(List.of(first, second));

        assertEquals(2, service.autoRefusePending());

        for (Reservation refused : List.of(first, second)) {
            assertEquals(ReservationStatus.REFUSED, refused.getStatus());
            assertEquals("no_answer", refused.getCancelReason());
            assertEquals(NOW, refused.getDecidedAt());
        }
        verify(trips).releaseSeats(unanswered.getId(), 1);
        verify(trips).releaseSeats(leavingSoon.getId(), 3);
        // Nothing was ever confirmed, so the lock count must not move.
        verify(trips, never()).releaseConfirmedSeats(any(), anyInt());
    }

    @Test
    @DisplayName("the job records the refusal with no actor, because nobody decided it")
    void autoRefuseRecordsAnEventWithoutAnActor() {
        Reservation pending = pendingReservation(tripNotLookedUpById(4, false), 1);
        when(reservations.findAutoRefusable(any(), any(), any())).thenReturn(List.of(pending));

        service.autoRefusePending();

        TripEvent event = savedEvent();
        assertEquals(TripEventType.RESERVATION_REFUSED, event.getType());
        assertNull(event.getActorId());
        assertEquals("no_answer", event.getDetail());
    }

    @Test
    @DisplayName("the waiting window and the departure cutoff are two hours and thirty minutes")
    void autoRefuseConstants() {
        assertEquals(Duration.ofHours(2), ReservationService.ANSWER_WINDOW);
        assertEquals(Duration.ofMinutes(30), ReservationService.AUTO_REFUSE_BEFORE_DEPARTURE);
    }

    @Test
    @DisplayName("a fixed clock makes the job's windows reproducible")
    void autoRefuseFollowsTheClock() {
        Instant later = NOW.plus(3, ChronoUnit.HOURS);
        ReservationService atLater = new ReservationService(reservations, trips, tripEvents,
                users, reputationService, Clock.fixed(later, ZoneOffset.UTC));
        when(reservations.findAutoRefusable(any(), any(), any())).thenReturn(List.of());

        atLater.autoRefusePending();

        verify(reservations).findAutoRefusable(ReservationStatus.PENDING,
                later.minus(2, ChronoUnit.HOURS), later.plus(30, ChronoUnit.MINUTES));
    }

    // --- helpers ------------------------------------------------------------------------------

    private ReservationDtos.BookRequest book(int seats) {
        return new ReservationDtos.BookRequest(seats);
    }

    private Trip givenTrip(int seatsTotal, boolean instantBooking) {
        Trip trip = tripLeavingAt(DEPARTURE, seatsTotal, instantBooking);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        return trip;
    }

    /**
     * For the paths that reach the trip through the reservation, so the service never looks
     * it up by id and stubbing findById would be an unused stub.
     */
    private Trip tripNotLookedUpById(int seatsTotal, boolean instantBooking) {
        return tripLeavingAt(DEPARTURE, seatsTotal, instantBooking);
    }

    private Trip tripLeavingAt(Instant departure, int seatsTotal, boolean instantBooking) {
        return new Trip(driver, null, "Tunis Centre", 36.8065, 10.1815, "Sousse", 35.8256, 10.6360,
                departure, seatsTotal, new BigDecimal("12.50"), instantBooking, null, 140_000,
                null, null);
    }

    private Reservation pendingReservation(Trip trip, int seats) {
        return new Reservation(trip, passenger, seats, "1234");
    }

    private void givenActivePassenger() {
        when(users.findById(passengerId)).thenReturn(Optional.of(passenger));
    }

    private void givenNoOtherReservations() {
        when(reservations.findByPassenger_IdAndStatusIn(eq(passengerId), any()))
                .thenReturn(List.of());
    }

    private void givenHeldReservationOn(Trip other) {
        when(reservations.findByPassenger_IdAndStatusIn(eq(passengerId), any()))
                .thenReturn(List.of(new Reservation(other, passenger, 1, "1111")));
    }

    private void givenSeatsCanBeHeld() {
        when(trips.holdSeats(any(), anyInt())).thenReturn(1);
    }

    private void givenOwnReservation(Reservation reservation) {
        when(reservations.findByIdAndPassenger_Id(reservation.getId(), passengerId))
                .thenReturn(Optional.of(reservation));
    }

    private Reservation savedReservation() {
        ArgumentCaptor<Reservation> saved = ArgumentCaptor.forClass(Reservation.class);
        verify(reservations).save(saved.capture());
        return saved.getValue();
    }

    private TripEvent savedEvent() {
        ArgumentCaptor<TripEvent> saved = ArgumentCaptor.forClass(TripEvent.class);
        verify(tripEvents).save(saved.capture());
        return saved.getValue();
    }

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<Set<ReservationStatus>> captureStatuses() {
        return (ArgumentCaptor<Set<ReservationStatus>>) (ArgumentCaptor<?>)
                ArgumentCaptor.forClass(Set.class);
    }

    @Test
    @DisplayName("every reservation status knows whether it holds a seat")
    void statusFlags() {
        assertTrue(ReservationStatus.PENDING.isActive());
        assertTrue(ReservationStatus.CONFIRMED.isActive());
        assertFalse(ReservationStatus.REFUSED.isActive());
        assertFalse(ReservationStatus.CANCELLED.isActive());
        assertFalse(ReservationStatus.NO_SHOW.isActive());
        assertFalse(ReservationStatus.COMPLETED.isActive());

        assertTrue(ReservationStatus.PENDING.awaitsDecision());
        assertFalse(ReservationStatus.CONFIRMED.awaitsDecision());

        assertTrue(ReservationStatus.CONFIRMED.holdsConfirmedSeat());
        assertFalse(ReservationStatus.PENDING.holdsConfirmedSeat());
        assertNotNull(ReservationStatus.valueOf("NO_SHOW"));
    }
}
