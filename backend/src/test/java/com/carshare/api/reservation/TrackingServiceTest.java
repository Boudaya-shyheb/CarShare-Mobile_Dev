package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
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
class TrackingServiceTest {
    private static final Instant NOW = Instant.parse("2026-11-20T08:00:00Z");
    private static final double ORIGIN_LAT = 36.8065;
    private static final double ORIGIN_LNG = 10.1815;
    private static final double DESTINATION_LAT = 35.8256;
    private static final double DESTINATION_LNG = 10.6360;

    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private GpsPointRepository gpsPoints;
    @Mock private TripEventRepository tripEvents;
    @Mock private UserRepository users;
    @Mock private ReservationService reservationService;
    @Mock private ReputationService reputationService;

    private TrackingService service;
    private AppUser driver;
    private AppUser passenger;
    private UUID driverId;

    @BeforeEach
    void setUp() {
        // A real TripService, so a geofence actually moves the trip through the state machine
        // and writes its event, rather than only recording that a mock was called.
        TripService tripService = new TripService(trips, tripEvents, users,
                reservationService, reputationService);
        lenient().when(reputationService.forUser(any()))
                .thenReturn(ReputationService.Reputation.NONE);
        lenient().when(reputationService.forUsers(any())).thenReturn(java.util.Map.of());
        lenient().when(reputationService.ratingsFor(any())).thenReturn(java.util.Map.of());

        service = new TrackingService(trips, reservations, gpsPoints, tripEvents, tripService,
                Clock.fixed(NOW, ZoneOffset.UTC));
        driver = new AppUser("Ahmed Driver", "+21611111111", "ahmed@carshare.tn", "hash",
                UserRole.DRIVER);
        passenger = new AppUser("Mouna Passenger", "+21622222222", "mouna@carshare.tn", "hash",
                UserRole.PASSENGER);
        driverId = driver.getId();
    }

    // --- which positions are kept -------------------------------------------------------------

    @Test
    @DisplayName("the first position of a trip is always kept")
    void keepsTheFirstPosition() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(), batch(point(farFromEverything(), NOW)));

        assertEquals(1, savedPoints().size());
        assertEquals(NOW, trip.getLastPositionAt());
    }

    @Test
    @DisplayName("a position older than the last one known is ignored")
    void ignoresStalePositions() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(farFromEverything()[0], farFromEverything()[1], NOW);

        service.reportPositions(driverId, trip.getId(),
                batch(point(farFromEverything(), NOW.minus(10, ChronoUnit.SECONDS))));

        verify(gpsPoints, never()).saveAll(any());
        assertEquals(NOW, trip.getLastPositionAt());
    }

    @Test
    @DisplayName("positions less than two seconds after the last kept one are dropped")
    void dropsPositionsBunchedTooClose() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(farFromEverything()[0], farFromEverything()[1], NOW);

        service.reportPositions(driverId, trip.getId(), batch(
                point(farFromEverything(), NOW.plusSeconds(1)),  // 1 s on, dropped
                point(farFromEverything(), NOW.plusSeconds(2)),  // 2 s on, kept
                point(farFromEverything(), NOW.plusSeconds(3)),  // 1 s after that, dropped
                point(farFromEverything(), NOW.plusSeconds(4))));  // kept

        List<GpsPoint> kept = savedPoints();
        assertEquals(2, kept.size());
        assertEquals(NOW.plusSeconds(2), kept.get(0).getRecordedAt());
        assertEquals(NOW.plusSeconds(4), kept.get(1).getRecordedAt());
        assertEquals(NOW.plusSeconds(4), trip.getLastPositionAt());
    }

    @Test
    @DisplayName("exactly two seconds apart is close enough to keep")
    void keepsPositionsExactlyTwoSecondsApart() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(farFromEverything()[0], farFromEverything()[1], NOW);

        service.reportPositions(driverId, trip.getId(),
                batch(point(farFromEverything(), NOW.plus(TrackingService.MIN_POSITION_GAP))));

        assertEquals(1, savedPoints().size());
        assertEquals(Duration.ofSeconds(2), TrackingService.MIN_POSITION_GAP);
    }

    @Test
    @DisplayName("a buffer that arrives out of order is sorted before it is filtered")
    void sortsTheBatchFirst() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(), batch(
                point(farFromEverything(), NOW.plusSeconds(6)),
                point(farFromEverything(), NOW.plusSeconds(2)),
                point(farFromEverything(), NOW.plusSeconds(4))));

        List<GpsPoint> kept = savedPoints();
        assertEquals(3, kept.size());
        assertEquals(NOW.plusSeconds(2), kept.get(0).getRecordedAt());
        assertEquals(NOW.plusSeconds(6), kept.get(2).getRecordedAt());
    }

    @Test
    @DisplayName("an empty, oversized or impossible batch is refused whole")
    void refusesABadBatch() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);
        UUID tripId = trip.getId();

        List<TrackingDtos.ReportPositionsRequest> bad = List.of(
                new TrackingDtos.ReportPositionsRequest(List.of()),
                new TrackingDtos.ReportPositionsRequest(fiftyOnePoints()),
                batch(new TrackingDtos.PositionPoint(95d, ORIGIN_LNG, null, NOW)),
                batch(new TrackingDtos.PositionPoint(ORIGIN_LAT, 190d, null, NOW)),
                batch(new TrackingDtos.PositionPoint(null, ORIGIN_LNG, null, NOW)),
                batch(new TrackingDtos.PositionPoint(ORIGIN_LAT, ORIGIN_LNG, null, null)),
                batch(new TrackingDtos.PositionPoint(ORIGIN_LAT, ORIGIN_LNG, -3f, NOW)));

        for (TrackingDtos.ReportPositionsRequest request : bad) {
            ApiException error = assertThrows(ApiException.class,
                    () -> service.reportPositions(driverId, tripId, request));
            assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
            assertEquals("invalid_positions", error.getCode());
        }
        verify(gpsPoints, never()).saveAll(any());
    }

    @Test
    @DisplayName("fifty points is the most one request may carry")
    void acceptsExactlyFiftyPoints() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);
        List<TrackingDtos.PositionPoint> fifty = new ArrayList<>();
        for (int i = 0; i < 50; i++) {
            fifty.add(point(farFromEverything(), NOW.plusSeconds(i * 3L)));
        }

        service.reportPositions(driverId, trip.getId(),
                new TrackingDtos.ReportPositionsRequest(fifty));

        assertEquals(50, savedPoints().size());
        assertEquals(50, TrackingService.MAX_POINTS_PER_REQUEST);
    }

    @Test
    @DisplayName("a trip that is not being tracked takes no positions")
    void refusesPositionsOutsideTracking() {
        Trip trip = givenOwnedTrip(TripStatus.SCHEDULED);

        ApiException error = assertThrows(ApiException.class, () -> service.reportPositions(
                driverId, trip.getId(), batch(point(farFromEverything(), NOW))));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("trip_not_tracking", error.getCode());
    }

    @Test
    @DisplayName("another driver cannot send positions, and is not told the trip exists")
    void refusesPositionsFromAnotherDriver() {
        UUID tripId = UUID.randomUUID();
        UUID stranger = UUID.randomUUID();
        when(trips.findByIdAndDriver_Id(tripId, stranger)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class, () -> service.reportPositions(
                stranger, tripId, batch(point(farFromEverything(), NOW))));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    // --- the pickup geofence ------------------------------------------------------------------

    @Test
    @DisplayName("99 m from the pickup point counts as having arrived")
    void arrivesAtNinetyNineMetres() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfOrigin(99), NOW)));

        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        TripEvent event = savedEvents().get(0);
        assertEquals(TripEventType.DRIVER_ARRIVED, event.getType());
        assertEquals("geofence", event.getDetail());
        assertEquals(driverId, event.getActorId());
        assertEquals(metresNorthOfOrigin(99)[0], event.getLat(), 1e-9);
    }

    @Test
    @DisplayName("101 m from the pickup point is not close enough")
    void doesNotArriveAtOneHundredAndOneMetres() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfOrigin(101), NOW)));

        assertEquals(TripStatus.DRIVER_EN_ROUTE, trip.getStatus());
        verifyNoInteractions(tripEvents);
        assertEquals(100d, TrackingService.GEOFENCE_RADIUS_M);
    }

    @Test
    @DisplayName("a buffer sitting at the pickup point arrives once, not once per point")
    void arrivesOnlyOnce() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(), batch(
                point(metresNorthOfOrigin(50), NOW),
                point(metresNorthOfOrigin(40), NOW.plusSeconds(3)),
                point(metresNorthOfOrigin(30), NOW.plusSeconds(6))));

        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        assertEquals(3, savedPoints().size());
        verify(tripEvents, times(1)).save(any());
    }

    @Test
    @DisplayName("a geofence crossed part-way through a buffer is still caught")
    void catchesAGeofenceMidBuffer() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(), batch(
                point(metresNorthOfOrigin(5_000), NOW),
                point(metresNorthOfOrigin(2_000), NOW.plusSeconds(3)),
                point(metresNorthOfOrigin(60), NOW.plusSeconds(6))));

        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
    }

    // --- the drop-off geofence ----------------------------------------------------------------

    @Test
    @DisplayName("reaching the drop-off point completes the trip and the rides")
    void dropOffCompletesEverything() {
        Trip trip = givenOwnedTrip(TripStatus.IN_PROGRESS);
        Reservation aboard = confirmedReservation(trip, 2);
        aboard.recordCheckIn(NOW.minus(30, ChronoUnit.MINUTES));
        givenConfirmedReservations(trip, aboard);

        service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfDestination(40), NOW)));

        assertEquals(TripStatus.COMPLETED, trip.getStatus());
        assertEquals(ReservationStatus.COMPLETED, aboard.getStatus());
        assertEquals(TripEventType.COMPLETED, savedEvents().get(0).getType());
    }

    @Test
    @DisplayName("a passenger who never boarded is left alone when the trip completes")
    void dropOffLeavesPassengersWhoNeverBoarded() {
        Trip trip = givenOwnedTrip(TripStatus.IN_PROGRESS);
        Reservation neverBoarded = confirmedReservation(trip, 1);
        givenConfirmedReservations(trip, neverBoarded);

        service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfDestination(40), NOW)));

        assertEquals(TripStatus.COMPLETED, trip.getStatus());
        assertEquals(ReservationStatus.CONFIRMED, neverBoarded.getStatus());
    }

    @Test
    @DisplayName("passing near the drop-off point before the ride starts changes nothing")
    void dropOffIgnoredBeforeTheRideStarts() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfDestination(10), NOW)));

        assertEquals(TripStatus.DRIVER_EN_ROUTE, trip.getStatus());
        verifyNoInteractions(tripEvents);
    }

    // --- the route deviation alert ------------------------------------------------------------

    @Test
    @DisplayName("more than 300 m off the planned route raises the alert once")
    void raisesTheDeviationAlert() {
        Trip trip = givenOwnedTripOnARoute(TripStatus.IN_PROGRESS);

        service.reportPositions(driverId, trip.getId(), batch(
                point(metresOffRoute(400), NOW),
                point(metresOffRoute(500), NOW.plusSeconds(3))));

        assertTrue(trip.isDeviating());
        List<TripEvent> events = savedEvents();
        assertEquals(1, events.size(), "a longer detour is still one alert");
        assertEquals(TripEventType.DEVIATION, events.get(0).getType());
        assertEquals(300d, TrackingService.DEVIATION_THRESHOLD_M);
    }

    @Test
    @DisplayName("coming back to within 300 m resolves the alert")
    void resolvesTheDeviationAlert() {
        Trip trip = givenOwnedTripOnARoute(TripStatus.IN_PROGRESS);

        service.reportPositions(driverId, trip.getId(), batch(
                point(metresOffRoute(400), NOW),
                point(metresOffRoute(100), NOW.plusSeconds(4))));

        assertFalse(trip.isDeviating());
        List<TripEvent> events = savedEvents();
        assertEquals(2, events.size());
        assertEquals(TripEventType.DEVIATION, events.get(0).getType());
        assertEquals(TripEventType.DEVIATION_RESOLVED, events.get(1).getType());
    }

    @Test
    @DisplayName("staying on the route writes nothing")
    void staysQuietOnTheRoute() {
        Trip trip = givenOwnedTripOnARoute(TripStatus.IN_PROGRESS);

        service.reportPositions(driverId, trip.getId(), batch(
                point(metresOffRoute(10), NOW),
                point(metresOffRoute(250), NOW.plusSeconds(3))));

        assertFalse(trip.isDeviating());
        verifyNoInteractions(tripEvents);
    }

    @Test
    @DisplayName("exactly 300 m off is not yet a deviation")
    void threeHundredMetresIsNotYetADeviation() {
        Trip trip = givenOwnedTripOnARoute(TripStatus.IN_PROGRESS);

        service.reportPositions(driverId, trip.getId(), batch(point(metresOffRoute(299), NOW)));

        assertFalse(trip.isDeviating());
        verifyNoInteractions(tripEvents);
    }

    @Test
    @DisplayName("with no planned route the deviation check is skipped")
    void skipsDeviationWithoutARoute() {
        Trip trip = givenOwnedTrip(TripStatus.IN_PROGRESS);

        service.reportPositions(driverId, trip.getId(), batch(point(metresOffRoute(5_000), NOW)));

        assertFalse(trip.isDeviating());
        verifyNoInteractions(tripEvents);
    }

    @Test
    @DisplayName("deviation is only watched once the ride is under way")
    void watchesDeviationOnlyInProgress() {
        Trip trip = givenOwnedTripOnARoute(TripStatus.DRIVER_EN_ROUTE);

        service.reportPositions(driverId, trip.getId(), batch(point(metresOffRoute(900), NOW)));

        assertFalse(trip.isDeviating());
        verifyNoInteractions(tripEvents);
    }

    // --- pickup check-in ----------------------------------------------------------------------

    @Test
    @DisplayName("the right code puts the passenger aboard")
    void rightCodeChecksIn() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);

        ReservationDtos.PassengerView result =
                service.checkIn(driverId, reservation.getId(), "1234");

        assertEquals(NOW, reservation.getCheckedInAt());
        assertTrue(reservation.isCheckedIn());
        assertEquals(ReservationStatus.CONFIRMED.name(), result.status());
        assertEquals(TripEventType.CHECK_IN, savedEvents().get(0).getType());
    }

    @Test
    @DisplayName("a code with spaces around it still works")
    void trimsTheCode() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);

        service.checkIn(driverId, reservation.getId(), "  1234  ");

        assertTrue(reservation.isCheckedIn());
    }

    @Test
    @DisplayName("a wrong code costs an attempt and says how many are left")
    void wrongCodeCountsAnAttempt() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);

        ApiException error = assertThrows(ApiException.class,
                () -> service.checkIn(driverId, reservation.getId(), "9999"));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("wrong_pickup_code", error.getCode());
        assertEquals(1, reservation.getPickupCodeAttempts());
        assertTrue(error.getMessage().contains("2"), error.getMessage());
        assertFalse(reservation.isCheckedIn());
    }

    @Test
    @DisplayName("the third wrong code locks check-in and records the failure")
    void thirdWrongCodeLocks() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);

        assertEquals("wrong_pickup_code", attemptAndCatch(reservation, "0000").getCode());
        assertEquals("wrong_pickup_code", attemptAndCatch(reservation, "1111").getCode());
        ApiException locked = attemptAndCatch(reservation, "2222");

        assertEquals(HttpStatus.CONFLICT, locked.getStatus());
        assertEquals("pickup_code_locked", locked.getCode());
        assertEquals(3, reservation.getPickupCodeAttempts());
        assertTrue(reservation.isPickupCodeLocked());
        assertEquals(TripEventType.CHECK_IN_FAILED, savedEvents().get(0).getType());
    }

    @Test
    @DisplayName("once locked, even the right code is refused and no second failure is recorded")
    void staysLockedAfterwards() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);
        for (String wrong : List.of("0000", "1111", "2222")) {
            attemptAndCatch(reservation, wrong);
        }

        ApiException error = attemptAndCatch(reservation, "1234");

        assertEquals("pickup_code_locked", error.getCode());
        assertEquals(3, reservation.getPickupCodeAttempts(), "a locked code costs no more attempts");
        verify(tripEvents, times(1)).save(any());
        assertFalse(reservation.isCheckedIn());
    }

    @Test
    @DisplayName("check-in only happens while the driver is waiting at the pickup point")
    void checkInNeedsAnArrivedTrip() {
        Trip trip = givenTrip(TripStatus.IN_PROGRESS);
        Reservation reservation = givenConfirmedReservationFor(trip);

        ApiException error = assertThrows(ApiException.class,
                () -> service.checkIn(driverId, reservation.getId(), "1234"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("trip_not_tracking", error.getCode());
    }

    @Test
    @DisplayName("a passenger cannot be checked in twice")
    void refusesASecondCheckIn() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);
        reservation.recordCheckIn(NOW.minus(1, ChronoUnit.MINUTES));

        ApiException error = assertThrows(ApiException.class,
                () -> service.checkIn(driverId, reservation.getId(), "1234"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("already_checked_in", error.getCode());
    }

    @Test
    @DisplayName("a reservation that was never confirmed cannot check in")
    void refusesCheckInForAnUnconfirmedReservation() {
        Trip trip = givenArrivedTrip();
        Reservation pending = new Reservation(trip, passenger, 1, "1234");
        when(reservations.findById(pending.getId())).thenReturn(Optional.of(pending));

        ApiException error = assertThrows(ApiException.class,
                () -> service.checkIn(driverId, pending.getId(), "1234"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_reservation_state", error.getCode());
    }

    @Test
    @DisplayName("another driver checking someone in gets a 404")
    void refusesCheckInFromAnotherDriver() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);

        ApiException error = assertThrows(ApiException.class,
                () -> service.checkIn(UUID.randomUUID(), reservation.getId(), "1234"));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    // --- boarding ------------------------------------------------------------------------------

    @Test
    @DisplayName("checking in the last passenger starts boarding")
    void lastCheckInStartsBoarding() {
        Trip trip = givenArrivedTrip();
        Reservation only = givenConfirmedReservationFor(trip);
        givenConfirmedReservations(trip, only);

        service.checkIn(driverId, only.getId(), "1234");

        assertEquals(TripStatus.PICKED_UP, trip.getStatus());
        assertEquals(TripEventType.PICKED_UP, savedEvents().get(1).getType());
        assertEquals("all_passengers_checked_in", savedEvents().get(1).getDetail());
    }

    @Test
    @DisplayName("boarding waits while another passenger is still expected")
    void boardingWaitsForEveryone() {
        Trip trip = givenArrivedTrip();
        Reservation first = givenConfirmedReservationFor(trip);
        Reservation second = confirmedReservation(trip, 1);
        givenConfirmedReservations(trip, first, second);

        service.checkIn(driverId, first.getId(), "1234");

        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        assertEquals(1, savedEvents().size());
    }

    @Test
    @DisplayName("a no-show for the last straggler starts boarding")
    void noShowForTheLastStragglerStartsBoarding() {
        Trip trip = givenArrivedTrip();
        Reservation aboard = confirmedReservation(trip, 1);
        aboard.recordCheckIn(NOW.minus(2, ChronoUnit.MINUTES));
        Reservation missing = givenConfirmedReservationFor(trip);
        givenArrivedFiveMinutesAgo(trip);
        // The no-show drops out of the confirmed list, leaving only the passenger aboard.
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of(aboard));

        service.markNoShow(driverId, missing.getId());

        assertEquals(ReservationStatus.NO_SHOW, missing.getStatus());
        assertEquals(TripStatus.PICKED_UP, trip.getStatus());
    }

    @Test
    @DisplayName("boarding does not start when nobody turned up at all")
    void boardingNeedsSomebodyAboard() {
        Trip trip = givenArrivedTrip();
        Reservation missing = givenConfirmedReservationFor(trip);
        givenArrivedFiveMinutesAgo(trip);
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of());

        service.markNoShow(driverId, missing.getId());

        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
    }

    // --- no-show -------------------------------------------------------------------------------

    @Test
    @DisplayName("a no-show after five minutes releases the seats")
    void noShowAfterFiveMinutes() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip, 2);
        givenArrivedFiveMinutesAgo(trip);

        ReservationDtos.PassengerView result = service.markNoShow(driverId, reservation.getId());

        assertEquals(ReservationStatus.NO_SHOW.name(), result.status());
        assertEquals(NOW, reservation.getDecidedAt());
        verify(trips).releaseSeats(trip.getId(), 2);
        verify(trips).releaseConfirmedSeats(trip.getId(), 2);
        assertEquals(TripEventType.NO_SHOW, savedEvents().get(0).getType());
    }

    @Test
    @DisplayName("one second short of five minutes is too early")
    void noShowAtFourFiftyNineIsTooEarly() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);
        givenArrivedAt(trip, NOW.minus(299, ChronoUnit.SECONDS));

        ApiException error = assertThrows(ApiException.class,
                () -> service.markNoShow(driverId, reservation.getId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("no_show_too_early", error.getCode());
        assertEquals(ReservationStatus.CONFIRMED, reservation.getStatus());
        verify(trips, never()).releaseSeats(any(), anyInt());
        assertEquals(Duration.ofMinutes(5), TrackingService.NO_SHOW_GRACE);
    }

    @Test
    @DisplayName("with no arrival on record a no-show is too early")
    void noShowNeedsAnArrivalOnRecord() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);
        when(tripEvents.findFirstByTrip_IdAndTypeOrderByCreatedAtDesc(trip.getId(),
                TripEventType.DRIVER_ARRIVED)).thenReturn(Optional.empty());

        assertEquals("no_show_too_early", assertThrows(ApiException.class,
                () -> service.markNoShow(driverId, reservation.getId())).getCode());
    }

    @Test
    @DisplayName("a passenger who is already aboard cannot be a no-show")
    void noShowRefusedForSomeoneAboard() {
        Trip trip = givenArrivedTrip();
        Reservation reservation = givenConfirmedReservationFor(trip);
        reservation.recordCheckIn(NOW.minus(1, ChronoUnit.MINUTES));

        assertEquals("already_checked_in", assertThrows(ApiException.class,
                () -> service.markNoShow(driverId, reservation.getId())).getCode());
    }

    @Test
    @DisplayName("a no-show needs the driver to be waiting at the pickup point")
    void noShowNeedsAnArrivedTrip() {
        Trip trip = givenTrip(TripStatus.IN_PROGRESS);
        Reservation reservation = givenConfirmedReservationFor(trip);

        assertEquals("trip_not_tracking", assertThrows(ApiException.class,
                () -> service.markNoShow(driverId, reservation.getId())).getCode());
    }

    // --- the live view -------------------------------------------------------------------------

    @Test
    @DisplayName("the driver sees the live view without any reservation of their own")
    void driverSeesTheLiveView() {
        Trip trip = givenTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(metresNorthOfOrigin(1_000)[0], ORIGIN_LNG, NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        TrackingDtos.LiveView view = service.live(driverId, trip.getId());

        assertEquals("DRIVER_EN_ROUTE", view.tripStatus());
        assertEquals("PICKUP", view.target());
        assertEquals(1_000, view.distanceToTargetM(), 3);
        assertEquals(NOW, view.lastPositionAt());
        assertNull(view.myReservationStatus());
        assertNull(view.checkedIn());
    }

    @Test
    @DisplayName("a confirmed passenger sees their own status and whether they are aboard")
    void passengerSeesTheirOwnStatus() {
        Trip trip = givenTrip(TripStatus.DRIVER_ARRIVED);
        trip.recordPosition(ORIGIN_LAT, ORIGIN_LNG, NOW);
        Reservation mine = confirmedReservation(trip, 1);
        mine.recordCheckIn(NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(eq(trip.getId()),
                eq(passenger.getId()), any())).thenReturn(Optional.of(mine));

        TrackingDtos.LiveView view = service.live(passenger.getId(), trip.getId());

        assertEquals("CONFIRMED", view.myReservationStatus());
        assertTrue(view.checkedIn());
        assertEquals(0, view.distanceToTargetM(), 2);
    }

    @Test
    @DisplayName("a passenger still sees the trip once it has completed")
    void completedPassengerStillSeesTheFinishedTrip() {
        Trip trip = givenTrip(TripStatus.COMPLETED);
        trip.recordPosition(DESTINATION_LAT, DESTINATION_LNG, NOW);
        Reservation mine = confirmedReservation(trip, 1);
        mine.recordCheckIn(NOW.minus(1, ChronoUnit.HOURS));
        mine.complete(NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(eq(trip.getId()),
                eq(passenger.getId()), any())).thenReturn(Optional.of(mine));

        TrackingDtos.LiveView view = service.live(passenger.getId(), trip.getId());

        assertEquals("COMPLETED", view.tripStatus());
        assertEquals("COMPLETED", view.myReservationStatus());
        assertEquals("DROPOFF", view.target());
        assertTrue(view.checkedIn());
        assertEquals(0, view.distanceToTargetM(), 2);
    }

    @Test
    @DisplayName("the live view is open to confirmed and completed reservations, nothing else")
    void onlyConfirmedAndCompletedMayWatch() {
        Trip trip = givenTrip(TripStatus.IN_PROGRESS);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(eq(trip.getId()),
                eq(passenger.getId()), any())).thenReturn(Optional.empty());

        assertThrows(ApiException.class, () -> service.live(passenger.getId(), trip.getId()));

        ArgumentCaptor<java.util.Collection<ReservationStatus>> statuses = captureStatuses();
        verify(reservations).findByTrip_IdAndPassenger_IdAndStatusIn(eq(trip.getId()),
                eq(passenger.getId()), statuses.capture());
        assertEquals(java.util.Set.of(ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED),
                java.util.Set.copyOf(statuses.getValue()));
    }

    @Test
    @DisplayName("somebody with no confirmed seat is not told the trip exists")
    void strangersCannotWatch() {
        Trip trip = givenTrip(TripStatus.IN_PROGRESS);
        UUID stranger = UUID.randomUUID();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(eq(trip.getId()), eq(stranger),
                any())).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.live(stranger, trip.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("the target switches from pickup to drop-off once the passengers are aboard")
    void targetFollowsTheTripStatus() {
        assertEquals(TrackingTarget.PICKUP, TripStatus.SCHEDULED.trackingTarget());
        assertEquals(TrackingTarget.PICKUP, TripStatus.DRIVER_EN_ROUTE.trackingTarget());
        assertEquals(TrackingTarget.PICKUP, TripStatus.DRIVER_ARRIVED.trackingTarget());
        assertEquals(TrackingTarget.DROPOFF, TripStatus.PICKED_UP.trackingTarget());
        assertEquals(TrackingTarget.DROPOFF, TripStatus.IN_PROGRESS.trackingTarget());
        assertEquals(TrackingTarget.DROPOFF, TripStatus.COMPLETED.trackingTarget());
        assertEquals(TrackingTarget.PICKUP, TripStatus.CANCELLED.trackingTarget());
    }

    @Test
    @DisplayName("the distance is measured to the drop-off point once the ride is under way")
    void measuresToTheDropOffWhenUnderWay() {
        Trip trip = givenTrip(TripStatus.IN_PROGRESS);
        trip.recordPosition(metresNorthOfDestination(2_000)[0], DESTINATION_LNG, NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        TrackingDtos.LiveView view = service.live(driverId, trip.getId());

        assertEquals("DROPOFF", view.target());
        assertEquals(2_000, view.distanceToTargetM(), 5);
    }

    @Test
    @DisplayName("with no speed on record the ETA uses the 8.3 m/s floor")
    void etaFallsBackToTheSpeedFloor() {
        Trip trip = givenTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(metresNorthOfOrigin(8_300)[0], ORIGIN_LNG, NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        TrackingDtos.LiveView view = service.live(driverId, trip.getId());

        assertEquals(1_000, view.etaSeconds(), 5);
        assertEquals(8.3d, TrackingService.MIN_ETA_SPEED_MPS);
    }

    @Test
    @DisplayName("a faster last speed shortens the ETA")
    void etaUsesTheLastKnownSpeed() {
        Trip trip = givenTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(metresNorthOfOrigin(10_000)[0], ORIGIN_LNG, NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(gpsPoints.findFirstByTrip_IdOrderByRecordedAtDesc(trip.getId())).thenReturn(
                Optional.of(new GpsPoint(trip, ORIGIN_LAT, ORIGIN_LNG, 25f, NOW)));

        assertEquals(400, service.live(driverId, trip.getId()).etaSeconds(), 3);
    }

    @Test
    @DisplayName("a slower last speed is lifted to the floor rather than used as is")
    void etaNeverUsesACrawl() {
        Trip trip = givenTrip(TripStatus.DRIVER_EN_ROUTE);
        trip.recordPosition(metresNorthOfOrigin(8_300)[0], ORIGIN_LNG, NOW);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(gpsPoints.findFirstByTrip_IdOrderByRecordedAtDesc(trip.getId())).thenReturn(
                Optional.of(new GpsPoint(trip, ORIGIN_LAT, ORIGIN_LNG, 0.5f, NOW)));

        assertEquals(1_000, service.live(driverId, trip.getId()).etaSeconds(), 5);
    }

    @Test
    @DisplayName("before the first position there is no distance or ETA to report")
    void liveViewWithoutAPositionYet() {
        Trip trip = givenTrip(TripStatus.DRIVER_EN_ROUTE);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        TrackingDtos.LiveView view = service.live(driverId, trip.getId());

        assertNull(view.lastLat());
        assertNull(view.lastLng());
        assertNull(view.lastPositionAt());
        assertNull(view.distanceToTargetM());
        assertNull(view.etaSeconds());
        assertFalse(view.deviating());
    }

    @Test
    @DisplayName("reporting positions answers with the same live view the passengers poll")
    void reportingPositionsReturnsTheLiveView() {
        Trip trip = givenOwnedTrip(TripStatus.DRIVER_EN_ROUTE);

        TrackingDtos.LiveView view = service.reportPositions(driverId, trip.getId(),
                batch(point(metresNorthOfOrigin(500), NOW)));

        assertEquals("DRIVER_EN_ROUTE", view.tripStatus());
        assertEquals("PICKUP", view.target());
        assertEquals(500, view.distanceToTargetM(), 3);
        assertEquals(NOW, view.lastPositionAt());
    }

    // --- helpers --------------------------------------------------------------------------------

    private Trip givenTrip(TripStatus status) {
        return tripAt(status, null);
    }

    /** A trip the driver owns, looked up the way reportPositions looks it up. */
    private Trip givenOwnedTrip(TripStatus status) {
        Trip trip = tripAt(status, null);
        when(trips.findByIdAndDriver_Id(trip.getId(), driverId)).thenReturn(Optional.of(trip));
        return trip;
    }

    private Trip givenOwnedTripOnARoute(TripStatus status) {
        Trip trip = tripAt(status, straightRoutePolyline());
        when(trips.findByIdAndDriver_Id(trip.getId(), driverId)).thenReturn(Optional.of(trip));
        return trip;
    }

    private Trip givenArrivedTrip() {
        return givenTrip(TripStatus.DRIVER_ARRIVED);
    }

    private Trip tripAt(TripStatus status, String routePolyline) {
        Trip trip = new Trip(driver, null, "Tunis Centre", ORIGIN_LAT, ORIGIN_LNG, "Sousse",
                DESTINATION_LAT, DESTINATION_LNG, NOW.plus(1, ChronoUnit.HOURS), 4,
                new BigDecimal("12.50"), false, null, 140_000, null, routePolyline);
        // Walk the state machine rather than assigning, so no test starts from an impossible state.
        for (TripStatus step : List.of(TripStatus.DRIVER_EN_ROUTE, TripStatus.DRIVER_ARRIVED,
                TripStatus.PICKED_UP, TripStatus.IN_PROGRESS, TripStatus.COMPLETED)) {
            if (trip.getStatus() == status) {
                break;
            }
            trip.applyStatus(step);
        }
        assertEquals(status, trip.getStatus(), "could not reach " + status);
        return trip;
    }

    private Reservation confirmedReservation(Trip trip, int seats) {
        Reservation reservation = new Reservation(trip, passenger, seats, "1234");
        reservation.confirm(NOW.minus(2, ChronoUnit.HOURS));
        return reservation;
    }

    private Reservation givenConfirmedReservationFor(Trip trip) {
        return givenConfirmedReservationFor(trip, 1);
    }

    private Reservation givenConfirmedReservationFor(Trip trip, int seats) {
        Reservation reservation = confirmedReservation(trip, seats);
        when(reservations.findById(reservation.getId())).thenReturn(Optional.of(reservation));
        return reservation;
    }

    private void givenConfirmedReservations(Trip trip, Reservation... held) {
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of(held));
    }

    private void givenArrivedFiveMinutesAgo(Trip trip) {
        givenArrivedAt(trip, NOW.minus(5, ChronoUnit.MINUTES));
    }

    private void givenArrivedAt(Trip trip, Instant when) {
        TripEvent arrival = new TripEvent(trip, TripEventType.DRIVER_ARRIVED, driverId, null, null,
                "geofence");
        setCreatedAt(arrival, when);
        when(tripEvents.findFirstByTrip_IdAndTypeOrderByCreatedAtDesc(trip.getId(),
                TripEventType.DRIVER_ARRIVED)).thenReturn(Optional.of(arrival));
    }

    /** createdAt is set by @PrePersist, which never runs against a mocked repository. */
    private static void setCreatedAt(TripEvent event, Instant when) {
        try {
            var field = TripEvent.class.getDeclaredField("createdAt");
            field.setAccessible(true);
            field.set(event, when);
        } catch (ReflectiveOperationException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    private ApiException attemptAndCatch(Reservation reservation, String code) {
        return assertThrows(ApiException.class,
                () -> service.checkIn(driverId, reservation.getId(), code));
    }

    private static TrackingDtos.ReportPositionsRequest batch(
            TrackingDtos.PositionPoint... points) {
        return new TrackingDtos.ReportPositionsRequest(List.of(points));
    }

    private static TrackingDtos.PositionPoint point(double[] at, Instant when) {
        return new TrackingDtos.PositionPoint(at[0], at[1], null, when);
    }

    private static List<TrackingDtos.PositionPoint> fiftyOnePoints() {
        List<TrackingDtos.PositionPoint> points = new ArrayList<>();
        for (int i = 0; i < 51; i++) {
            points.add(new TrackingDtos.PositionPoint(ORIGIN_LAT, ORIGIN_LNG, null,
                    NOW.plusSeconds(i * 3L)));
        }
        return points;
    }

    private static double[] metresNorthOfOrigin(double metres) {
        return new double[] { latPlus(ORIGIN_LAT, metres), ORIGIN_LNG };
    }

    private static double[] metresNorthOfDestination(double metres) {
        return new double[] { latPlus(DESTINATION_LAT, metres), DESTINATION_LNG };
    }

    /** Somewhere no geofence or route reaches, for the tests that only care about filtering. */
    private static double[] farFromEverything() {
        return new double[] { 34.0, 9.0 };
    }

    /**
     * The planned route runs due east along a parallel, well away from both geofences, so a point
     * this many metres north of it is exactly that far off route.
     */
    private static String straightRoutePolyline() {
        return PolylineFixture.encode(new double[][] {
                { ROUTE_LAT, ROUTE_MID_LNG - 0.10 }, { ROUTE_LAT, ROUTE_MID_LNG + 0.10 } });
    }

    private static double[] metresOffRoute(double metres) {
        return new double[] { latPlus(ROUTE_LAT, metres), ROUTE_MID_LNG };
    }

    private static final double ROUTE_LAT = 36.40;
    private static final double ROUTE_MID_LNG = 10.40;

    private static double latPlus(double latitude, double metres) {
        return latitude + metres * 180d / (Math.PI * GeoUtils.EARTH_RADIUS_M);
    }

    private List<GpsPoint> savedPoints() {
        ArgumentCaptor<List<GpsPoint>> saved = captureList();
        verify(gpsPoints).saveAll(saved.capture());
        return saved.getValue();
    }

    private List<TripEvent> savedEvents() {
        ArgumentCaptor<TripEvent> saved = ArgumentCaptor.forClass(TripEvent.class);
        verify(tripEvents, org.mockito.Mockito.atLeastOnce()).save(saved.capture());
        return saved.getAllValues();
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<java.util.Collection<ReservationStatus>> captureStatuses() {
        return (ArgumentCaptor<java.util.Collection<ReservationStatus>>) (ArgumentCaptor<?>)
                ArgumentCaptor.forClass(java.util.Collection.class);
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<List<GpsPoint>> captureList() {
        return (ArgumentCaptor<List<GpsPoint>>) (ArgumentCaptor<?>)
                ArgumentCaptor.forClass(List.class);
    }
}
