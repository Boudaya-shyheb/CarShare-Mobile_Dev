package com.carshare.api.reservation;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Closes the trips nobody started.
 *
 * <p>A trip still SCHEDULED more than {@link TripService#START_GRACE} after its planned departure
 * will not happen, but nothing else ever moves it, so it would sit in "Upcoming" for ever with its
 * seats held. The state machine only lets SCHEDULED go to CANCELLED (or start), so that is the
 * terminal state used, with a reason that says why. Driven every ten minutes by
 * {@link TripExpiryJob}, and a plain method so a test can run it on a fixed clock.
 */
@Service
public class TripExpiryService {
    static final String EXPIRED_REASON = "Expired: the driver never started this trip.";

    private final TripRepository trips;
    private final TripService tripService;
    private final ReservationService reservationService;
    private final Clock clock;

    public TripExpiryService(TripRepository trips, TripService tripService,
            ReservationService reservationService, Clock clock) {
        this.trips = trips;
        this.tripService = tripService;
        this.reservationService = reservationService;
        this.clock = clock;
    }

    /** @return how many trips were expired */
    @Transactional
    public int expireStaleTrips() {
        Instant cutoff = clock.instant().minus(TripService.START_GRACE);
        List<Trip> stale = trips.findByStatusAndDepartureTimeBefore(TripStatus.SCHEDULED, cutoff);
        for (Trip trip : stale) {
            // Through the state machine, so the CANCELLED event is written with the reason, and
            // no actor: nobody decided this, the start window simply ran out.
            tripService.changeStatus(trip, TripStatus.CANCELLED, null, null, null, EXPIRED_REASON);
            // Trip.cancel released every seat; this closes the reservations that held them.
            reservationService.cancelAllForCancelledTrip(trip, null);
        }
        return stale.size();
    }
}
