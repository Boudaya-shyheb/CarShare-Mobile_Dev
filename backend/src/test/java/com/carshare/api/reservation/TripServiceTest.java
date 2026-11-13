package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import com.carshare.api.vehicles.VehicleDtos;
import com.carshare.api.vehicles.VehicleService;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
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
class TripServiceTest {
    private static final double TUNIS_LAT = 36.8065;
    private static final double TUNIS_LNG = 10.1815;
    private static final double SOUSSE_LAT = 35.8256;
    private static final double SOUSSE_LNG = 10.6360;
    private static final BigDecimal PRICE = new BigDecimal("12.50");

    @Mock private TripRepository trips;
    @Mock private TripEventRepository tripEvents;
    @Mock private UserRepository users;
    @Mock private ReservationService reservationService;
    @Mock private ReputationService reputationService;
    @Mock private VehicleService vehicleService;

    private static final UUID VEHICLE_ID = UUID.randomUUID();

    private TripService service;
    private AppUser driver;
    private Instant departure;

    @BeforeEach
    void setUp() {
        service = new TripService(trips, tripEvents, users, reservationService,
                reputationService, vehicleService, Clock.systemUTC());
        lenient().when(reputationService.forUser(any()))
                .thenReturn(ReputationService.Reputation.NONE);
        lenient().when(reputationService.forUsers(any())).thenReturn(java.util.Map.of());
        lenient().when(reputationService.ratingsFor(any())).thenReturn(java.util.Map.of());

        driver = new AppUser("Yacine Jomni", "+21612345678", "driver@carshare.tn", "hash", UserRole.DRIVER);
        departure = Instant.now().plus(3, ChronoUnit.HOURS);
        approveLicense(driver, LocalDate.now().plusYears(2));
    }

    // --- publishing rules: licence and vehicle ------------------------------------------------

    private ApiException publishFailure(AppUser user) {
        when(users.findById(user.getId())).thenReturn(Optional.of(user));
        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(user.getId(), publishRequest()));
        verify(trips, never()).save(any(Trip.class));
        return error;
    }

    @Test
    @DisplayName("a driver who never submitted a licence gets license_not_verified")
    void publishNeedsASubmittedLicense() {
        AppUser fresh = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);

        ApiException error = publishFailure(fresh);

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("license_not_verified", error.getCode());
        verifyNoInteractions(vehicleService);
    }

    @Test
    @DisplayName("a licence still waiting for review is not enough")
    void publishNeedsAReviewedLicense() {
        AppUser pending = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);
        pending.submitDriverLicense(LocalDate.now().plusYears(2), new byte[] {1}, "image/png");

        ApiException error = publishFailure(pending);

        assertEquals("license_not_verified", error.getCode());
        assertTrue(error.getMessage().contains("waiting for review"));
    }

    @Test
    @DisplayName("a rejected licence tells the driver to scan it again")
    void publishRejectsARejectedLicense() {
        AppUser rejected = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);
        rejected.submitDriverLicense(LocalDate.now().plusYears(2), new byte[] {1}, "image/png");
        rejected.reviewDriverLicense("REJECTED", "blurry");

        ApiException error = publishFailure(rejected);

        assertEquals("license_not_verified", error.getCode());
        assertTrue(error.getMessage().contains("Scan it again"));
    }

    @Test
    @DisplayName("an approved licence that expires before the trip gives license_expired")
    void publishRejectsALicenseThatExpiresBeforeTheTrip() {
        AppUser expired = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);
        approveLicense(expired, LocalDate.now().minusDays(1));

        ApiException error = publishFailure(expired);

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("license_expired", error.getCode());
    }

    @Test
    @DisplayName("a licence that expires after the departure day is accepted")
    void publishAcceptsALicenseValidOnTheDay() {
        AppUser lastDay = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);
        approveLicense(lastDay, LocalDate.now().plusDays(2));
        when(users.findById(lastDay.getId())).thenReturn(Optional.of(lastDay));

        assertEquals("SCHEDULED", service.publish(lastDay.getId(), publishRequest()).status());
    }

    @Test
    @DisplayName("publishing without a vehicle gives vehicle_required")
    void publishNeedsAVehicle() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        TripDtos.PublishTripRequest noVehicle = new TripDtos.PublishTripRequest(null, "Tunis Centre",
                TUNIS_LAT, TUNIS_LNG, "Sousse", SOUSSE_LAT, SOUSSE_LNG, departure, 3, PRICE, false,
                null, 140_000, 7_200, null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), noVehicle));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("vehicle_required", error.getCode());
        verify(trips, never()).save(any(Trip.class));
    }

    @Test
    @DisplayName("the vehicle module decides ownership, approval and capacity, and its answer is passed on")
    void publishPassesTheVehicleModulesRefusalOn() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        doThrow(new ApiException(HttpStatus.CONFLICT, "vehicle_not_approved", "Not approved."))
                .when(vehicleService).validateForTrip(eq(driver.getId()), eq(VEHICLE_ID), anyInt());

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), publishRequest()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("vehicle_not_approved", error.getCode());
        verify(trips, never()).save(any(Trip.class));
    }

    @Test
    @DisplayName("a successful publish checks the vehicle with the seats offered and stores its id")
    void publishStoresTheChosenVehicle() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        TripDtos.TripDetail detail = service.publish(driver.getId(), publishRequest());

        verify(vehicleService).validateForTrip(driver.getId(), VEHICLE_ID, 3);
        assertEquals(VEHICLE_ID, detail.vehicleId());
    }

    @Test
    @DisplayName("editing a trip also needs a vehicle")
    void updateNeedsAVehicle() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        TripDtos.UpdateTripRequest noVehicle = new TripDtos.UpdateTripRequest(null, "Tunis Centre",
                TUNIS_LAT, TUNIS_LNG, "Sousse", SOUSSE_LAT, SOUSSE_LNG, departure, 3, PRICE, false,
                null, null, null, null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.update(driver.getId(), trip.getId(), noVehicle));

        assertEquals("vehicle_required", error.getCode());
    }

    // --- the car on a trip ------------------------------------------------------------------

    @Test
    @DisplayName("the driver and a confirmed passenger see the plate; a stranger does not")
    void vehiclePlateIsOnlyForTheDriverAndSeatHolders() {
        Trip trip = new Trip(driver, VEHICLE_ID, "Tunis Centre", TUNIS_LAT, TUNIS_LNG, "Sousse",
                SOUSSE_LAT, SOUSSE_LNG, departure, 3, PRICE, false, null, null, null, null);
        UUID passenger = UUID.randomUUID();
        UUID stranger = UUID.randomUUID();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservationService.wasPassengerOnTrip(trip.getId(), passenger)).thenReturn(true);
        when(reservationService.wasPassengerOnTrip(trip.getId(), stranger)).thenReturn(false);
        when(vehicleService.tripVehicle(any(), org.mockito.ArgumentMatchers.anyBoolean()))
                .thenReturn(new VehicleDtos.TripVehicle(VEHICLE_ID, "Peugeot", "208", 2022, "Black",
                        null, 4, true, false));

        service.vehicleOf(driver.getId(), trip.getId());
        service.vehicleOf(passenger, trip.getId());
        service.vehicleOf(stranger, trip.getId());

        verify(vehicleService, org.mockito.Mockito.times(2)).tripVehicle(VEHICLE_ID, true);
        verify(vehicleService).tripVehicle(VEHICLE_ID, false);
    }

    @Test
    @DisplayName("an old trip without a vehicle answers 404 vehicle_not_found")
    void vehicleOfATripWithoutOneIsNotFound() {
        Trip trip = scheduledTrip();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.vehicleOf(driver.getId(), trip.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("vehicle_not_found", error.getCode());
    }

    // --- upcoming never shows past trips ----------------------------------------------------

    @Test
    @DisplayName("upcoming hides a scheduled trip past its start window but keeps one already under way")
    void upcomingHidesExpiredScheduledTrips() {
        Trip stale = tripAt(Instant.now().minus(3, ChronoUnit.HOURS));
        Trip late = tripAt(Instant.now().minus(30, ChronoUnit.MINUTES));
        Trip underWay = tripAt(Instant.now().minus(5, ChronoUnit.HOURS));
        underWay.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        Trip future = tripAt(Instant.now().plus(1, ChronoUnit.HOURS));
        when(trips.findByDriver_IdAndStatusInOrderByDepartureTimeDesc(any(), any()))
                .thenReturn(List.of(future, late, underWay, stale));

        List<TripDtos.TripSummary> upcoming = service.listMine(driver.getId(), "upcoming");

        assertEquals(List.of(future.getId(), late.getId(), underWay.getId()),
                upcoming.stream().map(TripDtos.TripSummary::id).toList());
    }

    private Trip tripAt(Instant when) {
        return new Trip(driver, VEHICLE_ID, "Tunis Centre", TUNIS_LAT, TUNIS_LNG, "Sousse",
                SOUSSE_LAT, SOUSSE_LNG, when, 3, PRICE, false, null, null, null, null);
    }

    // --- publishing -------------------------------------------------------------------------

    @Test
    @DisplayName("publishing a trip stores it as SCHEDULED and writes a PUBLISHED event")
    void publishStoresScheduledTripAndEvent() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        TripDtos.TripDetail detail = service.publish(driver.getId(), publishRequest());

        assertEquals("SCHEDULED", detail.status());
        assertEquals(3, detail.seatsTotal());
        assertEquals(3, detail.seatsAvailable());
        assertEquals(0, detail.confirmedSeats());
        assertFalse(detail.locked());
        assertEquals(driver.getId(), detail.driverId());
        assertEquals("Tunis Centre", detail.originLabel());
        verify(trips).save(any(Trip.class));

        TripEvent event = capturedEvent();
        assertEquals(TripEventType.PUBLISHED, event.getType());
        assertEquals(driver.getId(), event.getActorId());
        assertEquals(TUNIS_LAT, event.getLat().doubleValue());
    }

    @Test
    @DisplayName("a passenger account cannot publish a trip")
    void publishRejectsPassengerAccount() {
        AppUser passenger = new AppUser("Ines", "+21698765432", "p@carshare.tn", "hash", UserRole.PASSENGER);
        when(users.findById(passenger.getId())).thenReturn(Optional.of(passenger));

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(passenger.getId(), publishRequest()));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("driver_role_required", error.getCode());
        verify(trips, never()).save(any(Trip.class));
    }

    @Test
    @DisplayName("a suspended driver cannot publish a trip")
    void publishRejectsSuspendedDriver() {
        driver.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(7, ChronoUnit.DAYS));
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), publishRequest()));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("account_suspended", error.getCode());
    }

    @Test
    @DisplayName("a banned driver cannot publish a trip")
    void publishRejectsBannedDriver() {
        driver.updateAccountStatus(UserStatus.BANNED, null);
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), publishRequest()));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("account_banned", error.getCode());
    }

    @Test
    @DisplayName("a suspension whose end date has passed no longer blocks publishing")
    void publishAllowsDriverWhoseSuspensionEnded() {
        driver.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().minus(1, ChronoUnit.HOURS));
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        assertEquals("SCHEDULED", service.publish(driver.getId(), publishRequest()).status());
    }

    @Test
    @DisplayName("a licence the daily job has marked EXPIRED gives license_expired")
    void publishRejectsAnExpiredLicenceStatus() {
        AppUser lapsed = new AppUser("Nour", "+21622222222", "nour@carshare.tn", "hash", UserRole.DRIVER);
        lapsed.submitDriverLicense(LocalDate.now().minusDays(2), new byte[] {1}, "image/png");
        lapsed.reviewDriverLicense("EXPIRED", null);

        ApiException error = publishFailure(lapsed);

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("license_expired", error.getCode());
    }

    @Test
    @DisplayName("a warned driver may still publish")
    void publishAllowsWarnedDriver() {
        driver.updateAccountStatus(UserStatus.WARNING, null);
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));

        assertEquals("SCHEDULED", service.publish(driver.getId(), publishRequest()).status());
    }

    @Test
    @DisplayName("the drop-off point must differ from the pickup point")
    void publishRejectsSameOriginAndDestination() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        TripDtos.PublishTripRequest request = new TripDtos.PublishTripRequest(null,
                "Tunis Centre", TUNIS_LAT, TUNIS_LNG, "Tunis Centre", TUNIS_LAT, TUNIS_LNG,
                departure, 3, PRICE, false, null, null, null, null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), request));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("same_origin_and_destination", error.getCode());
    }

    @Test
    @DisplayName("out-of-range coordinates are refused")
    void publishRejectsImpossibleCoordinates() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        TripDtos.PublishTripRequest request = new TripDtos.PublishTripRequest(null,
                "Nowhere", 95.0, TUNIS_LNG, "Sousse", SOUSSE_LAT, SOUSSE_LNG,
                departure, 3, PRICE, false, null, null, null, null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(driver.getId(), request));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_coordinates", error.getCode());
    }

    @Test
    @DisplayName("an unknown account is rejected as unauthorized")
    void publishRejectsUnknownAccount() {
        UUID unknown = UUID.randomUUID();
        when(users.findById(unknown)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.publish(unknown, publishRequest()));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals("account_not_found", error.getCode());
    }

    // --- editing ----------------------------------------------------------------------------

    @Test
    @DisplayName("a scheduled trip without confirmed reservations can be edited freely")
    void updateChangesScheduledTrip() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        Instant laterDeparture = departure.plus(1, ChronoUnit.HOURS);

        TripDtos.TripDetail detail = service.update(driver.getId(), trip.getId(),
                updateRequest(laterDeparture, new BigDecimal("18.00"), 4, "Meet by the station."));

        assertEquals(laterDeparture, detail.departureTime());
        assertEquals(new BigDecimal("18.00"), detail.pricePerSeat());
        assertEquals(4, detail.seatsTotal());
        assertEquals(4, detail.seatsAvailable());
        assertEquals("Meet by the station.", detail.notes());
        assertEquals(TripEventType.UPDATED, capturedEvent().getType());
    }

    @Test
    @DisplayName("another driver's trip looks like it does not exist")
    void updateRejectsTripOwnedBySomeoneElse() {
        UUID tripId = UUID.randomUUID();
        when(trips.findByIdAndDriver_Id(tripId, driver.getId())).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class, () -> service.update(driver.getId(),
                tripId, updateRequest(departure, PRICE, 3, null)));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("a trip can no longer be edited once the driver is en route")
    void updateRejectsTripThatHasStarted() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class, () -> service.update(driver.getId(),
                trip.getId(), updateRequest(departure, PRICE, 3, null)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("trip_not_editable", error.getCode());
    }

    @Test
    @DisplayName("price cannot change once a reservation is confirmed")
    void updateRejectsPriceChangeOnLockedTrip() {
        Trip trip = lockedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class, () -> service.update(driver.getId(),
                trip.getId(), updateRequest(departure, new BigDecimal("20.00"), 3, null)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("trip_locked", error.getCode());
    }

    @Test
    @DisplayName("departure time cannot change once a reservation is confirmed")
    void updateRejectsTimeChangeOnLockedTrip() {
        Trip trip = lockedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class, () -> service.update(driver.getId(),
                trip.getId(), updateRequest(departure.plus(30, ChronoUnit.MINUTES), PRICE, 3, null)));

        assertEquals("trip_locked", error.getCode());
    }

    @Test
    @DisplayName("the route cannot change once a reservation is confirmed")
    void updateRejectsRouteChangeOnLockedTrip() {
        Trip trip = lockedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        TripDtos.UpdateTripRequest request = new TripDtos.UpdateTripRequest(null,
                "Tunis Centre", TUNIS_LAT, TUNIS_LNG, "Monastir", 35.7643, 10.8113,
                departure, 3, PRICE, false, null, null, null, null);

        ApiException error = assertThrows(ApiException.class,
                () -> service.update(driver.getId(), trip.getId(), request));

        assertEquals("trip_locked", error.getCode());
    }

    @Test
    @DisplayName("notes and instant booking stay editable on a locked trip")
    void updateAllowsNotesChangeOnLockedTrip() {
        Trip trip = lockedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        TripDtos.TripDetail detail = service.update(driver.getId(), trip.getId(),
                updateRequest(departure, PRICE, 3, "Bring a small bag only."));

        assertEquals("Bring a small bag only.", detail.notes());
        assertTrue(detail.locked());
        assertEquals(TripEventType.UPDATED, capturedEvent().getType());
    }

    @Test
    @DisplayName("seats cannot drop below the seats already confirmed")
    void updateRejectsSeatsBelowConfirmed() {
        Trip trip = scheduledTrip();
        trip.recordConfirmedSeats(2);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class, () -> service.update(driver.getId(),
                trip.getId(), updateRequest(departure, PRICE, 1, null)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("seats_below_reserved", error.getCode());
    }

    // --- cancelling -------------------------------------------------------------------------

    @Test
    @DisplayName("cancelling a scheduled trip records the reason and a CANCELLED event")
    void cancelRecordsReasonAndEvent() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        TripDtos.TripDetail detail = service.cancel(driver.getId(), trip.getId(), "  Car broke down  ");

        assertEquals("CANCELLED", detail.status());
        assertEquals("Car broke down", detail.cancelReason());
        TripEvent event = capturedEvent();
        assertEquals(TripEventType.CANCELLED, event.getType());
        assertEquals("Car broke down", event.getDetail());
    }

    @Test
    @DisplayName("a trip can still be cancelled while the driver is en route")
    void cancelAllowedWhileEnRoute() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        assertEquals("CANCELLED",
                service.cancel(driver.getId(), trip.getId(), "Passenger unreachable").status());
    }

    @Test
    @DisplayName("a trip can no longer be cancelled once the driver has arrived")
    void cancelRefusedAfterArrival() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        trip.applyStatus(TripStatus.DRIVER_ARRIVED);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.cancel(driver.getId(), trip.getId(), "Changed my mind"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_trip_transition", error.getCode());
        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        verify(tripEvents, never()).save(any(TripEvent.class));
    }

    @Test
    @DisplayName("cancelling releases the held seats")
    void cancelReleasesSeats() {
        Trip trip = scheduledTrip();
        trip.recordConfirmedSeats(2);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        TripDtos.TripDetail detail = service.cancel(driver.getId(), trip.getId(), "Trip called off");

        assertEquals(3, detail.seatsAvailable());
        assertEquals(0, detail.confirmedSeats());
        assertFalse(detail.locked());
    }

    // --- cancelling as an admin --------------------------------------------------------------

    @Test
    @DisplayName("an admin cancel records the reason, names the admin and closes the reservations")
    void adminCancelRecordsReasonAndActor() {
        Trip trip = scheduledTrip();
        trip.recordConfirmedSeats(2);
        UUID adminId = UUID.randomUUID(); // not the driver
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        TripDtos.TripDetail detail =
                service.cancelAsAdmin(adminId, trip.getId(), "  Reported by two riders  ");

        assertEquals("CANCELLED", detail.status());
        assertEquals("Reported by two riders", detail.cancelReason());
        assertEquals(3, detail.seatsAvailable()); // the seats are released
        assertEquals(0, detail.confirmedSeats());
        TripEvent event = capturedEvent();
        assertEquals(TripEventType.CANCELLED, event.getType());
        assertEquals(adminId, event.getActorId());
        assertEquals("Reported by two riders", event.getDetail());
        verify(reservationService).cancelAllForCancelledTrip(trip, adminId);
    }

    @Test
    @DisplayName("an admin cannot cancel a trip the state machine no longer lets move to CANCELLED")
    void adminCancelFollowsTheStateMachine() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        trip.applyStatus(TripStatus.DRIVER_ARRIVED);
        UUID adminId = UUID.randomUUID();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.cancelAsAdmin(adminId, trip.getId(), "Too late"));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_trip_transition", error.getCode());
        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        verify(tripEvents, never()).save(any(TripEvent.class));
        verify(reservationService, never()).cancelAllForCancelledTrip(any(), any());
    }

    @Test
    @DisplayName("an admin cancel of an unknown trip is a 404")
    void adminCancelOfUnknownTripIs404() {
        UUID missing = UUID.randomUUID();
        when(trips.findById(missing)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.cancelAsAdmin(UUID.randomUUID(), missing, "Whatever"));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("cancelling a trip hands its live reservations to the reservation service")
    void cancelClosesReservations() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        service.cancel(driver.getId(), trip.getId(), "Car broke down");

        verify(reservationService).cancelAllForCancelledTrip(trip, driver.getId());
    }

    @Test
    @DisplayName("a trip that cannot be cancelled leaves its reservations alone")
    void refusedCancelLeavesReservationsAlone() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        trip.applyStatus(TripStatus.DRIVER_ARRIVED);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        assertThrows(ApiException.class,
                () -> service.cancel(driver.getId(), trip.getId(), "Changed my mind"));

        verifyNoInteractions(reservationService);
    }

    // --- status transitions -----------------------------------------------------------------

    @Test
    @DisplayName("the driver walks the trip through every status in order")
    void changeStatusWalksTheHappyPath() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        List<TripStatus> path = List.of(TripStatus.DRIVER_EN_ROUTE, TripStatus.DRIVER_ARRIVED,
                TripStatus.PICKED_UP, TripStatus.IN_PROGRESS, TripStatus.COMPLETED);
        for (TripStatus next : path) {
            TripDtos.TripDetail detail = service.changeStatus(driver.getId(), trip.getId(),
                    new TripDtos.ChangeStatusRequest(next, TUNIS_LAT, TUNIS_LNG));
            assertEquals(next.name(), detail.status());
        }

        ArgumentCaptor<TripEvent> captor = ArgumentCaptor.forClass(TripEvent.class);
        verify(tripEvents, org.mockito.Mockito.times(5)).save(captor.capture());
        assertEquals(path.stream().map(TripEventType::forStatus).toList(),
                captor.getAllValues().stream().map(TripEvent::getType).toList());
    }

    @Test
    @DisplayName("a status cannot be skipped")
    void changeStatusRejectsSkippingAhead() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.changeStatus(driver.getId(), trip.getId(),
                        new TripDtos.ChangeStatusRequest(TripStatus.IN_PROGRESS, null, null)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("invalid_trip_transition", error.getCode());
        assertEquals(TripStatus.SCHEDULED, trip.getStatus());
        verify(tripEvents, never()).save(any(TripEvent.class));
    }

    @Test
    @DisplayName("a completed trip cannot move again")
    void changeStatusRejectsMovingACompletedTrip() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        trip.applyStatus(TripStatus.DRIVER_ARRIVED);
        trip.applyStatus(TripStatus.PICKED_UP);
        trip.applyStatus(TripStatus.IN_PROGRESS);
        trip.applyStatus(TripStatus.COMPLETED);
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.changeStatus(driver.getId(), trip.getId(),
                        new TripDtos.ChangeStatusRequest(TripStatus.IN_PROGRESS, null, null)));

        assertEquals("invalid_trip_transition", error.getCode());
    }

    @Test
    @DisplayName("cancelling through the status endpoint is refused so a reason is always stored")
    void changeStatusRefusesCancellationWithoutReason() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.changeStatus(driver.getId(), UUID.randomUUID(),
                        new TripDtos.ChangeStatusRequest(TripStatus.CANCELLED, null, null)));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("cancel_reason_required", error.getCode());
        verifyNoInteractions(trips);
    }

    @Test
    @DisplayName("an impossible position on a transition is refused")
    void changeStatusRejectsInvalidPosition() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class,
                () -> service.changeStatus(driver.getId(), trip.getId(),
                        new TripDtos.ChangeStatusRequest(TripStatus.DRIVER_EN_ROUTE, 200.0, 10.0)));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_coordinates", error.getCode());
        assertEquals(TripStatus.SCHEDULED, trip.getStatus());
    }

    // --- listing ----------------------------------------------------------------------------

    @Test
    @DisplayName("an unknown scope is rejected instead of silently listing everything")
    void listMineRejectsUnknownScope() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.listMine(driver.getId(), "archived"));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_trip_scope", error.getCode());
    }

    @Test
    @DisplayName("the upcoming scope asks for the statuses a trip passes through")
    void listMineUpcomingUsesActiveStatuses() {
        Trip trip = scheduledTrip();
        when(trips.findByDriver_IdAndStatusInOrderByDepartureTimeDesc(driver.getId(),
                java.util.Set.of(TripStatus.SCHEDULED, TripStatus.DRIVER_EN_ROUTE,
                        TripStatus.DRIVER_ARRIVED, TripStatus.PICKED_UP, TripStatus.IN_PROGRESS)))
                .thenReturn(List.of(trip));

        List<TripDtos.TripSummary> summaries = service.listMine(driver.getId(), "upcoming");

        assertEquals(1, summaries.size());
        assertEquals(trip.getId(), summaries.get(0).id());
        assertEquals("SCHEDULED", summaries.get(0).status());
    }

    @Test
    @DisplayName("a missing scope lists every trip of the driver")
    void listMineWithoutScopeListsEverything() {
        when(trips.findByDriver_IdOrderByDepartureTimeDesc(driver.getId()))
                .thenReturn(List.of(scheduledTrip()));

        assertEquals(1, service.listMine(driver.getId(), null).size());
    }

    @Test
    @DisplayName("a trip that does not exist is reported as not found")
    void getRejectsUnknownTrip() {
        UUID tripId = UUID.randomUUID();
        when(trips.findById(tripId)).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class, () -> service.get(tripId));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("the event log is readable by the driver and by a passenger who was aboard")
    void listEventsIsOpenToParticipants() {
        Trip trip = scheduledTrip();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(tripEvents.findByTrip_IdOrderByCreatedAtAsc(trip.getId())).thenReturn(List.of());

        assertTrue(service.listEvents(driver.getId(), trip.getId()).isEmpty());

        UUID passengerId = UUID.randomUUID();
        when(reservationService.wasPassengerOnTrip(trip.getId(), passengerId)).thenReturn(true);
        assertTrue(service.listEvents(passengerId, trip.getId()).isEmpty());
    }

    @Test
    @DisplayName("somebody who was never on the trip cannot read its event log")
    void listEventsHidesTheTripFromStrangers() {
        Trip trip = scheduledTrip();
        UUID stranger = UUID.randomUUID();
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservationService.wasPassengerOnTrip(trip.getId(), stranger)).thenReturn(false);

        ApiException error = assertThrows(ApiException.class,
                () -> service.listEvents(stranger, trip.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("trip_not_found", error.getCode());
    }

    @Test
    @DisplayName("a freshly published trip has no cancel reason")
    void publishedTripHasNoCancelReason() {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        assertNull(service.publish(driver.getId(), publishRequest()).cancelReason());
    }

    @Test
    @DisplayName("setting off by hand is refused while a confirmed passenger has not boarded")
    void refusesManualPickUpWithPassengersLeftBehind() {
        Trip trip = arrivedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        when(reservationService.hasPassengersStillToBoard(trip.getId())).thenReturn(true);

        ApiException error = assertThrows(ApiException.class, () -> service.changeStatus(
                driver.getId(), trip.getId(),
                new TripDtos.ChangeStatusRequest(TripStatus.PICKED_UP, null, null)));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("passengers_not_boarded", error.getCode());
        assertEquals(TripStatus.DRIVER_ARRIVED, trip.getStatus());
        verifyNoInteractions(tripEvents);
    }

    @Test
    @DisplayName("setting off by hand is allowed once everybody is settled")
    void allowsManualPickUpWhenEverybodyIsSettled() {
        Trip trip = arrivedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        when(reservationService.hasPassengersStillToBoard(trip.getId())).thenReturn(false);

        TripDtos.TripDetail detail = service.changeStatus(driver.getId(), trip.getId(),
                new TripDtos.ChangeStatusRequest(TripStatus.PICKED_UP, null, null));

        assertEquals(TripStatus.PICKED_UP.name(), detail.status());
        assertEquals(TripStatus.PICKED_UP, trip.getStatus());
    }

    @Test
    @DisplayName("a trip with nobody aboard may still set off by hand")
    void allowsManualPickUpWithNoPassengers() {
        Trip trip = arrivedTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));
        // No confirmed reservations at all, so nothing is left to board.
        when(reservationService.hasPassengersStillToBoard(trip.getId())).thenReturn(false);

        assertEquals(TripStatus.PICKED_UP.name(), service.changeStatus(driver.getId(), trip.getId(),
                new TripDtos.ChangeStatusRequest(TripStatus.PICKED_UP, null, null)).status());
    }

    @Test
    @DisplayName("the boarding check does not get in the way of the other transitions")
    void boardingCheckOnlyGuardsPickUp() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        service.changeStatus(driver.getId(), trip.getId(),
                new TripDtos.ChangeStatusRequest(TripStatus.DRIVER_EN_ROUTE, null, null));

        assertEquals(TripStatus.DRIVER_EN_ROUTE, trip.getStatus());
        verify(reservationService, never()).hasPassengersStillToBoard(any());
    }

    @Test
    @DisplayName("an impossible transition is still reported as one, not as unboarded passengers")
    void wrongStatusStillReportsTheTransition() {
        Trip trip = scheduledTrip();
        when(trips.findByIdAndDriver_Id(trip.getId(), driver.getId())).thenReturn(Optional.of(trip));

        ApiException error = assertThrows(ApiException.class, () -> service.changeStatus(
                driver.getId(), trip.getId(),
                new TripDtos.ChangeStatusRequest(TripStatus.PICKED_UP, null, null)));

        assertEquals("invalid_trip_transition", error.getCode());
        verify(reservationService, never()).hasPassengersStillToBoard(any());
    }

    /** A trip walked up to DRIVER_ARRIVED through the state machine. */
    private Trip arrivedTrip() {
        Trip trip = scheduledTrip();
        trip.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        trip.applyStatus(TripStatus.DRIVER_ARRIVED);
        return trip;
    }

    // --- helpers ----------------------------------------------------------------------------

    private static void approveLicense(AppUser user, LocalDate expiry) {
        user.submitDriverLicense(expiry, new byte[] {1}, "image/png");
        user.reviewDriverLicense("APPROVED", null);
    }

    private TripDtos.PublishTripRequest publishRequest() {
        return new TripDtos.PublishTripRequest(VEHICLE_ID, "Tunis Centre", TUNIS_LAT, TUNIS_LNG,
                "Sousse", SOUSSE_LAT, SOUSSE_LNG, departure, 3, PRICE, false, null, 140_000,
                7_200, null);
    }

    private TripDtos.UpdateTripRequest updateRequest(Instant departureTime, BigDecimal price,
            int seatsTotal, String notes) {
        return new TripDtos.UpdateTripRequest(VEHICLE_ID, "Tunis Centre", TUNIS_LAT, TUNIS_LNG,
                "Sousse", SOUSSE_LAT, SOUSSE_LNG, departureTime, seatsTotal, price, false, notes,
                null, null, null);
    }

    private Trip scheduledTrip() {
        return new Trip(driver, null, "Tunis Centre", TUNIS_LAT, TUNIS_LNG, "Sousse",
                SOUSSE_LAT, SOUSSE_LNG, departure, 3, PRICE, false, null, null, null, null);
    }

    private Trip lockedTrip() {
        Trip trip = scheduledTrip();
        trip.recordConfirmedSeats(1);
        return trip;
    }

    private TripEvent capturedEvent() {
        ArgumentCaptor<TripEvent> captor = ArgumentCaptor.forClass(TripEvent.class);
        verify(tripEvents).save(captor.capture());
        return captor.getValue();
    }
}
