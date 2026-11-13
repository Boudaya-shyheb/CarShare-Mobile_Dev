package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.ActiveUserGuard;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Ratings left after a trip has finished.
 *
 * <p>Who may rate whom is decided entirely by what happened on the trip: the passenger has to
 * have boarded (checked in, reservation COMPLETED), and the driver may only rate people who
 * boarded. Nobody can rate a trip they were not on, and nobody rates themselves.
 */
@Service
public class RatingService {

    private final RatingRepository ratings;
    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final UserRepository users;

    public RatingService(RatingRepository ratings, TripRepository trips,
            ReservationRepository reservations, UserRepository users) {
        this.ratings = ratings;
        this.trips = trips;
        this.reservations = reservations;
        this.users = users;
    }

    @Transactional
    public RatingDtos.RatingView rate(UUID raterId, UUID tripId, RatingDtos.RateRequest request) {
        ActiveUserGuard.requireActive(users, raterId);
        Instant now = Instant.now();
        Trip trip = completedTrip(tripId, raterId);
        AppUser rated = ratablePartner(trip, raterId, request.toUserId());

        if (ratings.existsByTrip_IdAndFrom_IdAndTo_Id(tripId, raterId, request.toUserId())) {
            throw new ApiException(HttpStatus.CONFLICT, "already_rated",
                    "You have already rated them for this trip. Edit that rating instead.");
        }
        AppUser rater = users.findById(raterId).orElseThrow(RatingService::tripNotFound);
        Rating rating = ratings.save(
                new Rating(trip, rater, rated, request.stars(), trimmed(request.comment())));
        return RatingDtos.RatingView.from(rating, now);
    }

    @Transactional
    public RatingDtos.RatingView revise(UUID raterId, UUID tripId, UUID ratedId,
            RatingDtos.ReviseRatingRequest request) {
        ActiveUserGuard.requireActive(users, raterId);
        Instant now = Instant.now();
        completedTrip(tripId, raterId);
        Rating rating = ratings.findByTrip_IdAndFrom_IdAndTo_Id(tripId, raterId, ratedId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "rating_not_found",
                        "You have not rated them for this trip yet."));
        if (!rating.isEditableAt(now)) {
            throw new ApiException(HttpStatus.CONFLICT, "rating_locked",
                    "A rating can only be changed within 24 hours of leaving it.");
        }
        rating.revise(request.stars(), trimmed(request.comment()));
        return RatingDtos.RatingView.from(rating, now);
    }

    /** Everyone the caller may rate on this trip, with whatever they have already left. */
    @Transactional(readOnly = true)
    public RatingDtos.MyRatings mine(UUID callerId, UUID tripId) {
        Instant now = Instant.now();
        Trip trip = trips.findById(tripId).orElseThrow(RatingService::tripNotFound);
        if (!wasOnTrip(trip, callerId)) throw tripNotFound();

        boolean completed = trip.getStatus() == TripStatus.COMPLETED;
        List<RatingDtos.RatableParty> parties = new ArrayList<>();
        for (AppUser partner : partnersFor(trip, callerId)) {
            Optional<Rating> existing = ratings.findByTrip_IdAndFrom_IdAndTo_Id(
                    tripId, callerId, partner.getId());
            parties.add(new RatingDtos.RatableParty(partner.getId(), partner.getFullName(),
                    trip.isDrivenBy(callerId) ? "PASSENGER" : "DRIVER",
                    existing.map(rating -> RatingDtos.RatingView.from(rating, now)).orElse(null)));
        }
        return new RatingDtos.MyRatings(tripId, completed, List.copyOf(parties));
    }

    // --- rules ---------------------------------------------------------------------------------

    private Trip completedTrip(UUID tripId, UUID callerId) {
        Trip trip = trips.findById(tripId).orElseThrow(RatingService::tripNotFound);
        if (!wasOnTrip(trip, callerId)) throw tripNotFound();
        if (trip.getStatus() != TripStatus.COMPLETED) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_completed",
                    "You can rate someone once the trip is finished.");
        }
        return trip;
    }

    /** The driver, or a passenger who actually boarded. */
    private boolean wasOnTrip(Trip trip, UUID userId) {
        return trip.isDrivenBy(userId) || boardedReservation(trip.getId(), userId).isPresent();
    }

    private Optional<Reservation> boardedReservation(UUID tripId, UUID passengerId) {
        return reservations
                .findByTrip_IdAndPassenger_IdAndStatusIn(tripId, passengerId,
                        Set.of(ReservationStatus.COMPLETED))
                .filter(Reservation::isCheckedIn);
    }

    /** Checks that the named person is someone the caller is allowed to rate on this trip. */
    private AppUser ratablePartner(Trip trip, UUID raterId, UUID ratedId) {
        if (raterId.equals(ratedId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "cannot_rate_yourself",
                    "You cannot rate yourself.");
        }
        for (AppUser partner : partnersFor(trip, raterId)) {
            if (partner.getId().equals(ratedId)) return partner;
        }
        throw new ApiException(HttpStatus.BAD_REQUEST, "not_on_this_trip",
                "You can only rate the people who travelled with you.");
    }

    /**
     * A passenger's only partner is the driver; the driver's partners are the passengers who
     * boarded. Someone refused, cancelled or marked a no-show never appears.
     */
    private List<AppUser> partnersFor(Trip trip, UUID callerId) {
        if (trip.isDrivenBy(callerId)) {
            List<AppUser> passengers = new ArrayList<>();
            for (Reservation reservation : reservations.findByTrip_IdAndStatusIn(trip.getId(),
                    Set.of(ReservationStatus.COMPLETED))) {
                if (reservation.isCheckedIn()) passengers.add(reservation.getPassenger());
            }
            return passengers;
        }
        return boardedReservation(trip.getId(), callerId).isPresent()
                ? List.of(trip.getDriver())
                : List.of();
    }

    private static String trimmed(String comment) {
        if (comment == null) return null;
        String text = comment.trim();
        return text.isEmpty() ? null : text;
    }

    private static ApiException tripNotFound() {
        // 404 rather than 403, so these routes cannot be used to probe other people's trips.
        return new ApiException(HttpStatus.NOT_FOUND, "trip_not_found",
                "This trip is no longer available.");
    }
}
