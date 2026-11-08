package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserStatus;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ReservationService {
    /** A driver has this long to answer a seat request before it is refused for them. */
    static final Duration ANSWER_WINDOW = Duration.ofHours(2);

    /** A request still pending this close to departure is refused, however recent it is. */
    static final Duration AUTO_REFUSE_BEFORE_DEPARTURE = Duration.ofMinutes(30);

    /** Cancelling earlier than this before departure carries no late-cancellation mark. */
    static final Duration FREE_CANCELLATION_WINDOW = Duration.ofHours(2);

    static final String NO_ANSWER = "no_answer";
    static final String TRIP_CANCELLED = "trip_cancelled";
    static final String REFUSED_BY_DRIVER = "refused_by_driver";
    static final String LATE_CANCELLATION = "late_cancellation";

    /** Reservations that hold a seat and block an overlapping booking. */
    private static final Set<ReservationStatus> ACTIVE =
            Set.of(ReservationStatus.PENDING, ReservationStatus.CONFIRMED);
    private static final Set<ReservationStatus> FINISHED =
            Set.of(ReservationStatus.COMPLETED, ReservationStatus.NO_SHOW);
    private static final Set<ReservationStatus> CALLED_OFF =
            Set.of(ReservationStatus.CANCELLED, ReservationStatus.REFUSED);

    private final ReservationRepository reservations;
    private final TripRepository trips;
    private final TripEventRepository tripEvents;
    private final UserRepository users;
    private final Clock clock;

    public ReservationService(ReservationRepository reservations, TripRepository trips,
            TripEventRepository tripEvents, UserRepository users, Clock clock) {
        this.reservations = reservations;
        this.trips = trips;
        this.tripEvents = tripEvents;
        this.users = users;
        this.clock = clock;
    }

    // --- passenger ---------------------------------------------------------------------------

    @Transactional
    public ReservationDtos.ReservationDetail book(UUID passengerId, UUID tripId,
            ReservationDtos.BookRequest request) {
        Instant now = clock.instant();
        AppUser passenger = requireBookingPassenger(passengerId);
        Trip trip = trips.findById(tripId).orElseThrow(ReservationService::tripNotFound);
        if (trip.isDrivenBy(passengerId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "own_trip",
                    "You cannot book a seat on a trip you are driving.");
        }
        if (!trip.getStatus().acceptsReservations() || !trip.getDepartureTime().isAfter(now)) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_bookable",
                    "This trip is no longer taking reservations.");
        }
        // Booking the same trip twice is an overlap with itself, so this covers that too.
        requireNoOverlap(passengerId, trip);

        int seats = request.seats();
        boolean instant = trip.isInstantBooking();
        if (trips.holdSeats(tripId, seats) == 0) {
            throw seatsUnavailable();
        }

        Reservation reservation = new Reservation(trip, passenger, seats, PickupCode.generate());
        TripEventType event = TripEventType.RESERVATION_REQUESTED;
        if (instant) {
            reservation.confirm(now);
            if (trips.addConfirmedSeats(tripId, seats) == 0) {
                throw seatsUnavailable();
            }
            event = TripEventType.RESERVATION_CONFIRMED;
        }
        reservations.save(reservation);
        tripEvents.save(new TripEvent(trip, event, passengerId, null, null, seatsDetail(seats)));
        return ReservationDtos.ReservationDetail.forPassenger(reservation);
    }

    @Transactional(readOnly = true)
    public List<ReservationDtos.ReservationDetail> listMine(UUID passengerId, String scope) {
        String wanted = scope == null || scope.isBlank()
                ? "all" : scope.trim().toLowerCase(Locale.ROOT);
        List<Reservation> found = switch (wanted) {
            case "all" -> reservations.findByPassenger_IdOrderByCreatedAtDesc(passengerId);
            case "upcoming" -> reservations
                    .findByPassenger_IdAndStatusInOrderByCreatedAtDesc(passengerId, ACTIVE);
            case "past" -> reservations
                    .findByPassenger_IdAndStatusInOrderByCreatedAtDesc(passengerId, FINISHED);
            case "cancelled" -> reservations
                    .findByPassenger_IdAndStatusInOrderByCreatedAtDesc(passengerId, CALLED_OFF);
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_reservation_scope",
                    "Choose upcoming, past, or cancelled.");
        };
        return found.stream().map(ReservationDtos.ReservationDetail::forPassenger).toList();
    }

    @Transactional
    public ReservationDtos.ReservationDetail cancel(UUID passengerId, UUID reservationId,
            String reason) {
        String cleaned = reason == null ? "" : reason.trim();
        if (cleaned.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "cancel_reason_required",
                    "Tell the driver why you are cancelling.");
        }
        Instant now = clock.instant();
        Reservation reservation = reservations.findByIdAndPassenger_Id(reservationId, passengerId)
                .orElseThrow(ReservationService::reservationNotFound);
        if (!reservation.getStatus().isActive()) {
            throw invalidReservationState(reservation, "cancelled");
        }
        Trip trip = reservation.getTrip();
        boolean confirmed = reservation.getStatus().holdsConfirmedSeat();
        // Free up to exactly two hours before departure; later is still allowed, but marked.
        boolean late = now.isAfter(trip.getDepartureTime().minus(FREE_CANCELLATION_WINDOW));

        reservation.cancel(cleaned, late, now);
        releaseSeats(trip, reservation.getSeats(), confirmed);
        tripEvents.save(new TripEvent(trip, TripEventType.RESERVATION_CANCELLED, passengerId,
                null, null, late ? LATE_CANCELLATION : cleaned));
        return ReservationDtos.ReservationDetail.forPassenger(reservation);
    }

    // --- driver -----------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<ReservationDtos.PassengerView> listForTrip(UUID driverId, UUID tripId) {
        requireOwnTrip(driverId, tripId);
        return reservations.findByTrip_IdOrderByCreatedAtAsc(tripId).stream()
                .map(ReservationDtos.PassengerView::from).toList();
    }

    @Transactional
    public ReservationDtos.PassengerView accept(UUID driverId, UUID reservationId) {
        Instant now = clock.instant();
        Reservation reservation = requireDecidableReservation(driverId, reservationId);
        Trip trip = reservation.getTrip();
        if (!trip.getStatus().acceptsReservations()) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_bookable",
                    "This trip is no longer taking reservations.");
        }
        reservation.confirm(now);
        if (trips.addConfirmedSeats(trip.getId(), reservation.getSeats()) == 0) {
            throw seatsUnavailable();
        }
        tripEvents.save(new TripEvent(trip, TripEventType.RESERVATION_CONFIRMED, driverId,
                null, null, seatsDetail(reservation.getSeats())));
        return ReservationDtos.PassengerView.from(reservation);
    }

    @Transactional
    public ReservationDtos.PassengerView refuse(UUID driverId, UUID reservationId) {
        Instant now = clock.instant();
        Reservation reservation = requireDecidableReservation(driverId, reservationId);
        Trip trip = reservation.getTrip();
        reservation.refuse(REFUSED_BY_DRIVER, now);
        releaseSeats(trip, reservation.getSeats(), false);
        tripEvents.save(new TripEvent(trip, TripEventType.RESERVATION_REFUSED, driverId,
                null, null, REFUSED_BY_DRIVER));
        return ReservationDtos.PassengerView.from(reservation);
    }

    // --- driven by other parts of the module -------------------------------------------------

    /**
     * Called by TripService once a trip has moved to CANCELLED. Trip.cancel has already released
     * every seat on the trip in one go, so this only closes the reservations.
     */
    @Transactional
    void cancelAllForCancelledTrip(Trip trip, UUID actorId) {
        Instant now = clock.instant();
        for (Reservation reservation : reservations.findByTrip_IdAndStatusIn(trip.getId(), ACTIVE)) {
            reservation.cancel(TRIP_CANCELLED, false, now);
            tripEvents.save(new TripEvent(trip, TripEventType.RESERVATION_CANCELLED, actorId,
                    null, null, TRIP_CANCELLED));
        }
    }

    /**
     * Refuses the seat requests a driver never answered. Driven every minute by
     * {@link ReservationAutoRefuseJob}, and a plain method so a test can run it on a fixed clock.
     *
     * @return how many reservations were refused
     */
    @Transactional
    public int autoRefusePending() {
        Instant now = clock.instant();
        List<Reservation> stale = reservations.findAutoRefusable(ReservationStatus.PENDING,
                now.minus(ANSWER_WINDOW), now.plus(AUTO_REFUSE_BEFORE_DEPARTURE));
        for (Reservation reservation : stale) {
            Trip trip = reservation.getTrip();
            reservation.refuse(NO_ANSWER, now);
            releaseSeats(trip, reservation.getSeats(), false);
            // No actor id: nobody decided this, the waiting window simply ran out.
            tripEvents.save(new TripEvent(trip, TripEventType.RESERVATION_REFUSED, null,
                    null, null, NO_ANSWER));
        }
        return stale.size();
    }

    // --- helpers ----------------------------------------------------------------------------

    private void releaseSeats(Trip trip, int seats, boolean wasConfirmed) {
        trips.releaseSeats(trip.getId(), seats);
        if (wasConfirmed) {
            trips.releaseConfirmedSeats(trip.getId(), seats);
        }
    }

    private void requireNoOverlap(UUID passengerId, Trip wanted) {
        for (Reservation held : reservations.findByPassenger_IdAndStatusIn(passengerId, ACTIVE)) {
            if (held.getTrip().overlaps(wanted)) {
                throw new ApiException(HttpStatus.CONFLICT, "overlapping_reservation",
                        "You already hold a reservation on a trip at that time.");
            }
        }
    }

    private AppUser requireBookingPassenger(UUID userId) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        if (user.getAccountStatus() == UserStatus.SUSPENDED
                || user.getAccountStatus() == UserStatus.BANNED) {
            throw new ApiException(HttpStatus.FORBIDDEN, "account_restricted",
                    "Your account is restricted, so you cannot book a seat.");
        }
        return user;
    }

    private Reservation requireDecidableReservation(UUID driverId, UUID reservationId) {
        Reservation reservation = requireReservationOnOwnTrip(driverId, reservationId);
        if (!reservation.getStatus().awaitsDecision()) {
            throw invalidReservationState(reservation, "answered");
        }
        return reservation;
    }

    private Reservation requireReservationOnOwnTrip(UUID driverId, UUID reservationId) {
        Reservation reservation = reservations.findById(reservationId)
                .orElseThrow(ReservationService::reservationNotFound);
        if (!reservation.getTrip().isDrivenBy(driverId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_trip_owner",
                    "Only the driver of this trip can answer its seat requests.");
        }
        return reservation;
    }

    private void requireOwnTrip(UUID driverId, UUID tripId) {
        Trip trip = trips.findById(tripId).orElseThrow(ReservationService::tripNotFound);
        if (!trip.isDrivenBy(driverId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_trip_owner",
                    "Only the driver of this trip can see who booked it.");
        }
    }

    private static ApiException invalidReservationState(Reservation reservation, String what) {
        return new ApiException(HttpStatus.CONFLICT, "invalid_reservation_state",
                "This reservation is " + label(reservation.getStatus())
                        + ", so it can no longer be " + what + ".");
    }

    private static ApiException seatsUnavailable() {
        return new ApiException(HttpStatus.CONFLICT, "seats_unavailable",
                "Those seats have just been taken.");
    }

    private static ApiException reservationNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "reservation_not_found",
                "This reservation could not be found.");
    }

    private static ApiException tripNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "trip_not_found",
                "This trip could not be found.");
    }

    private static String label(ReservationStatus status) {
        return status.name().toLowerCase(Locale.ROOT).replace('_', ' ');
    }

    private static String seatsDetail(int seats) {
        return seats + (seats == 1 ? " seat" : " seats");
    }
}
