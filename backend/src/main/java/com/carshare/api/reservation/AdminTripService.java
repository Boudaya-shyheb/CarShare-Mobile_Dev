package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * What an admin can see and do with one trip. The URL space is admin-only (SecurityConfig), so
 * nothing here checks the caller's role. Nothing here changes a trip directly either: cancelling
 * goes through {@link TripService}, so the state machine and the seat rules still apply.
 */
@Service
public class AdminTripService {
    /** Trips that are under way: the driver has set off and the ride is not finished. */
    private static final Set<TripStatus> IN_PROGRESS = EnumSet.of(TripStatus.DRIVER_EN_ROUTE,
            TripStatus.DRIVER_ARRIVED, TripStatus.PICKED_UP, TripStatus.IN_PROGRESS);

    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final TripEventRepository tripEvents;
    private final TripService tripService;

    public AdminTripService(TripRepository trips, ReservationRepository reservations,
            TripEventRepository tripEvents, TripService tripService) {
        this.trips = trips;
        this.reservations = reservations;
        this.tripEvents = tripEvents;
        this.tripService = tripService;
    }

    /** The trip, who booked it (never with a pickup code) and its events, oldest first. */
    @Transactional(readOnly = true)
    public AdminTripDtos.AdminTripDetail get(UUID tripId) {
        Trip trip = trips.findById(tripId).orElseThrow(AdminTripService::tripNotFound);
        List<ReservationDtos.PassengerView> passengers = reservations
                .findByTrip_IdOrderByCreatedAtAsc(tripId).stream()
                .map(ReservationDtos.PassengerView::from)
                .toList();
        List<TripDtos.EventView> events = tripEvents.findByTrip_IdOrderByCreatedAtAsc(tripId)
                .stream().map(TripDtos.EventView::from).toList();
        return new AdminTripDtos.AdminTripDetail(TripDtos.TripDetail.from(trip), passengers, events);
    }

    /** Calls a trip off on behalf of the admin. The rules are the driver's own cancel rules. */
    @Transactional
    public TripDtos.TripDetail cancel(UUID adminId, UUID tripId, String reason) {
        return tripService.cancelAsAdmin(adminId, tripId, reason);
    }

    /** The figures the dashboard shows for trips and reservations. */
    @Transactional(readOnly = true)
    public AdminTripDtos.TripCounts counts() {
        return new AdminTripDtos.TripCounts(trips.count(), trips.countByStatusIn(IN_PROGRESS),
                trips.countByStatus(TripStatus.COMPLETED), trips.countByStatus(TripStatus.CANCELLED),
                reservations.count());
    }

    private static ApiException tripNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "trip_not_found", "This trip could not be found.");
    }
}
