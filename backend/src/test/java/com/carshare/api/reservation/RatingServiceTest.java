package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

/** Who may rate whom, and when. */
@ExtendWith(MockitoExtension.class)
class RatingServiceTest {

    @Mock private RatingRepository ratings;
    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private UserRepository users;

    private RatingService service;
    private AppUser driver;
    private AppUser passenger;
    private Trip trip;

    @BeforeEach
    void setUp() {
        service = new RatingService(ratings, trips, reservations, users);
        driver = new AppUser("Ahmed Driver", "+21611111111", "ahmed@carshare.tn", "hash",
                UserRole.DRIVER);
        passenger = new AppUser("Mariem Rider", "+21622222222", "mariem@carshare.tn", "hash",
                UserRole.PASSENGER);
        trip = new Trip(driver, null, "Tunis", 36.8, 10.18, "Sousse", 35.82, 10.63,
                Instant.now().minus(3, ChronoUnit.HOURS), 3, new BigDecimal("12.00"), true,
                null, null, null, null);
    }

    // --- the happy path ------------------------------------------------------------------------

    @Test
    @DisplayName("a passenger who boarded can rate the driver once the trip is finished")
    void passengerRatesTheDriver() {
        givenCompletedTrip();
        givenBoardedPassenger();
        when(users.findById(passenger.getId())).thenReturn(Optional.of(passenger));
        when(ratings.existsByTrip_IdAndFrom_IdAndTo_Id(any(), any(), any())).thenReturn(false);
        when(ratings.save(any())).thenAnswer(call -> call.getArgument(0));

        RatingDtos.RatingView view = service.rate(passenger.getId(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, "  Smooth drive  "));

        assertEquals(5, view.stars());
        assertEquals(driver.getId(), view.toUserId());
        // A comment is trimmed, so stray spaces do not become content.
        assertEquals("Smooth drive", view.comment());
        assertTrue(view.editable());
        assertNotNull(view.createdAt());
    }

    @Test
    @DisplayName("the driver can rate a passenger who boarded")
    void driverRatesThePassenger() {
        givenCompletedTrip();
        givenOneBoardedPassengerOnTheTrip();
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(ratings.existsByTrip_IdAndFrom_IdAndTo_Id(any(), any(), any())).thenReturn(false);
        when(ratings.save(any())).thenAnswer(call -> call.getArgument(0));

        RatingDtos.RatingView view = service.rate(driver.getId(), trip.getId(),
                new RatingDtos.RateRequest(passenger.getId(), 4, null));

        assertEquals(4, view.stars());
        assertNull(view.comment());
    }

    // --- the rules -----------------------------------------------------------------------------

    @Test
    @DisplayName("nobody can rate before the trip has finished")
    void cannotRateAnUnfinishedTrip() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip)); // still SCHEDULED
        givenBoardedPassenger();

        ApiException thrown = assertThrows(ApiException.class, () -> service.rate(
                passenger.getId(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, null)));

        assertEquals("trip_not_completed", thrown.getCode());
        assertEquals(HttpStatus.CONFLICT, thrown.getStatus());
        verify(ratings, never()).save(any());
    }

    @Test
    @DisplayName("a passenger who never checked in was not really on the trip")
    void aNoShowCannotRate() {
        givenCompletedTrip();
        // COMPLETED reservation, but the driver never typed the code: not a participant.
        Reservation notBoarded = new Reservation(trip, passenger, 1, "1234");
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(any(), any(), any()))
                .thenReturn(Optional.of(notBoarded));

        ApiException thrown = assertThrows(ApiException.class, () -> service.rate(
                passenger.getId(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, null)));

        assertEquals("trip_not_found", thrown.getCode());
    }

    @Test
    @DisplayName("a stranger gets a 404, not a 403, so the route cannot be used to probe trips")
    void strangersSeeNothing() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(any(), any(), any()))
                .thenReturn(Optional.empty());

        ApiException thrown = assertThrows(ApiException.class, () -> service.rate(
                UUID.randomUUID(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, null)));

        assertEquals(HttpStatus.NOT_FOUND, thrown.getStatus());
        assertEquals("trip_not_found", thrown.getCode());
    }

    @Test
    @DisplayName("you cannot rate yourself")
    void cannotRateYourself() {
        givenCompletedTrip();
        // No passenger stub: the self check fires before the partner list is ever read.

        ApiException thrown = assertThrows(ApiException.class, () -> service.rate(
                driver.getId(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, null)));

        assertEquals("cannot_rate_yourself", thrown.getCode());
    }

    @Test
    @DisplayName("a second rating for the same pair is refused; the first is edited instead")
    void oneRatingPerPair() {
        givenCompletedTrip();
        givenBoardedPassenger();
        when(ratings.existsByTrip_IdAndFrom_IdAndTo_Id(any(), any(), any())).thenReturn(true);

        ApiException thrown = assertThrows(ApiException.class, () -> service.rate(
                passenger.getId(), trip.getId(),
                new RatingDtos.RateRequest(driver.getId(), 5, null)));

        assertEquals("already_rated", thrown.getCode());
        assertEquals(HttpStatus.CONFLICT, thrown.getStatus());
        verify(ratings, never()).save(any());
    }

    // --- the edit window -----------------------------------------------------------------------

    @Test
    @DisplayName("a rating can be changed while the 24 hour window is open")
    void revisesInsideTheWindow() {
        givenCompletedTrip();
        givenBoardedPassenger();
        Rating existing = new Rating(trip, passenger, driver, 2, "Late");
        when(ratings.findByTrip_IdAndFrom_IdAndTo_Id(trip.getId(), passenger.getId(),
                driver.getId())).thenReturn(Optional.of(existing));

        RatingDtos.RatingView view = service.revise(passenger.getId(), trip.getId(),
                driver.getId(), new RatingDtos.ReviseRatingRequest(4, "Was unfair"));

        assertEquals(4, view.stars());
        assertEquals("Was unfair", view.comment());
    }

    @Test
    @DisplayName("the window measures from when the rating was left, and closes after a day")
    void theWindowClosesAfterADay() {
        Rating rating = new Rating(trip, passenger, driver, 3, null);
        Instant left = rating.getCreatedAt();

        assertTrue(rating.isEditableAt(left.plus(23, ChronoUnit.HOURS)));
        assertFalse(rating.isEditableAt(left.plus(25, ChronoUnit.HOURS)));
        assertEquals(java.time.Duration.ofHours(24), Rating.EDIT_WINDOW);
    }

    // --- what the completion screen asks for -----------------------------------------------------

    @Test
    @DisplayName("a passenger is offered their driver, with whatever they already said")
    void minePresentsTheDriver() {
        givenCompletedTrip();
        givenBoardedPassenger();
        when(ratings.findByTrip_IdAndFrom_IdAndTo_Id(any(), any(), any()))
                .thenReturn(Optional.empty());

        RatingDtos.MyRatings mine = service.mine(passenger.getId(), trip.getId());

        assertTrue(mine.tripCompleted());
        assertEquals(1, mine.parties().size());
        assertEquals(driver.getId(), mine.parties().get(0).userId());
        assertEquals("DRIVER", mine.parties().get(0).role());
        assertNull(mine.parties().get(0).myRating());
    }

    @Test
    @DisplayName("a driver is offered every passenger who boarded, and nobody else")
    void minePresentsTheBoardedPassengers() {
        givenCompletedTrip();
        givenOneBoardedPassengerOnTheTrip();
        when(ratings.findByTrip_IdAndFrom_IdAndTo_Id(any(), any(), any()))
                .thenReturn(Optional.empty());

        RatingDtos.MyRatings mine = service.mine(driver.getId(), trip.getId());

        assertEquals(1, mine.parties().size());
        assertEquals(passenger.getId(), mine.parties().get(0).userId());
        assertEquals("PASSENGER", mine.parties().get(0).role());
    }

    // --- helpers ---------------------------------------------------------------------------------

    private void givenCompletedTrip() {
        walkTo(TripStatus.COMPLETED);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
    }

    /** The caller is a passenger who boarded this trip. */
    private void givenBoardedPassenger() {
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(any(), any(), any()))
                .thenReturn(Optional.of(boarded()));
    }

    /** The trip carries one passenger who boarded, which is what the driver may rate. */
    private void givenOneBoardedPassengerOnTheTrip() {
        when(reservations.findByTrip_IdAndStatusIn(trip.getId(),
                Set.of(ReservationStatus.COMPLETED))).thenReturn(List.of(boarded()));
    }

    private Reservation boarded() {
        Reservation reservation = new Reservation(trip, passenger, 1, "1234");
        reservation.confirm(Instant.now().minus(4, ChronoUnit.HOURS));
        reservation.recordCheckIn(Instant.now().minus(3, ChronoUnit.HOURS));
        reservation.complete(Instant.now().minus(1, ChronoUnit.HOURS));
        return reservation;
    }

    private void walkTo(TripStatus target) {
        for (TripStatus step : List.of(TripStatus.DRIVER_EN_ROUTE, TripStatus.DRIVER_ARRIVED,
                TripStatus.PICKED_UP, TripStatus.IN_PROGRESS, TripStatus.COMPLETED)) {
            trip.applyStatus(step);
            if (step == target) return;
        }
    }
}
