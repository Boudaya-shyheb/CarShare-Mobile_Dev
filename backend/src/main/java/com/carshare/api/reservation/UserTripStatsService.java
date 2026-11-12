package com.carshare.api.reservation;

import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The figures on a user's own profile card. Read-only, and about one user: the caller.
 *
 * <p>The rating and the reliability come from {@link ReputationService}, so they are exactly the
 * numbers a search result and the match score use.
 */
@Service
public class UserTripStatsService {
    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final ReputationService reputation;

    public UserTripStatsService(TripRepository trips, ReservationRepository reservations,
            ReputationService reputation) {
        this.trips = trips;
        this.reservations = reservations;
        this.reputation = reputation;
    }

    @Transactional(readOnly = true)
    public UserTripStatsDtos.UserTripStats statsFor(UUID userId) {
        long asDriver = trips.countByDriver_IdAndStatus(userId, TripStatus.COMPLETED);
        long asPassenger =
                reservations.countByPassenger_IdAndStatus(userId, ReservationStatus.COMPLETED);
        long noShows = reservations.countByPassenger_IdAndStatus(userId, ReservationStatus.NO_SHOW);
        ReputationService.Reputation standing = reputation.forUser(userId);
        return new UserTripStatsDtos.UserTripStats(asDriver, asPassenger, asDriver + asPassenger,
                standing.average(), standing.count(), noShows,
                MatchScorer.driverReliabilityPoints(standing.average(), standing.punctuality()));
    }
}
