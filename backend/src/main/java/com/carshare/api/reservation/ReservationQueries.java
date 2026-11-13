package com.carshare.api.reservation;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The reservation module's read-only face for the rest of the application.
 *
 * <p>Other modules inject <strong>this</strong> rather than reaching for our repositories or
 * entities. Everything it returns is a small record, so nothing outside the module ends up
 * holding a JPA entity whose lazy associations would blow up once the transaction closes, and
 * we stay free to change the tables without breaking anyone.
 *
 * <p>Nothing here writes. A module that needs a trip or a reservation changed calls the REST
 * API like any other client, so the business rules run.
 */
@Service
public class ReservationQueries {

    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final TripEventRepository tripEvents;
    private final GpsPointRepository gpsPoints;

    public ReservationQueries(TripRepository trips, ReservationRepository reservations,
            TripEventRepository tripEvents, GpsPointRepository gpsPoints) {
        this.trips = trips;
        this.reservations = reservations;
        this.tripEvents = tripEvents;
        this.gpsPoints = gpsPoints;
    }

    /** Who was involved in a trip: the driver, and the passengers who still hold a seat. */
    public record Participant(UUID userId, String fullName, String role, String reservationStatus,
            boolean checkedIn) { }

    /** The facts another module is likely to need about a trip, without the entity. */
    public record TripFacts(UUID tripId, UUID driverId, String originLabel, String destinationLabel,
            Instant departureTime, Instant expectedArrival, String status, int seatsTotal,
            int seatsAvailable, UUID vehicleId) { }

    public record EventFact(String type, UUID actorId, Instant at, Double lat, Double lng) { }

    public record TrackPoint(double lat, double lng, Instant recordedAt) { }

    /** Statuses that mean a passenger was, or still is, really on the trip. */
    private static final Set<ReservationStatus> REAL_PARTICIPANTS = Set.of(
            ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED, ReservationStatus.NO_SHOW);

    @Transactional(readOnly = true)
    public Optional<TripFacts> tripFacts(UUID tripId) {
        return trips.findById(tripId).map(trip -> new TripFacts(trip.getId(),
                trip.getDriver().getId(), trip.getOriginLabel(), trip.getDestinationLabel(),
                trip.getDepartureTime(), trip.expectedArrival(), trip.getStatus().name(),
                trip.getSeatsTotal(), trip.getSeatsAvailable(), trip.getVehicleId()));
    }

    /** The driver first, then every passenger who held a seat. Empty if the trip is unknown. */
    @Transactional(readOnly = true)
    public List<Participant> participants(UUID tripId) {
        return trips.findById(tripId).map(trip -> {
            List<Participant> people = new java.util.ArrayList<>();
            people.add(new Participant(trip.getDriver().getId(), trip.getDriver().getFullName(),
                    "DRIVER", null, false));
            for (Reservation reservation
                    : reservations.findByTrip_IdAndStatusIn(tripId, REAL_PARTICIPANTS)) {
                people.add(new Participant(reservation.getPassenger().getId(),
                        reservation.getPassenger().getFullName(), "PASSENGER",
                        reservation.getStatus().name(), reservation.isCheckedIn()));
            }
            return List.copyOf(people);
        }).orElseGet(List::of);
    }

    /** True when this user drove the trip or held a seat on it. The usual authorisation check. */
    @Transactional(readOnly = true)
    public boolean wasOnTrip(UUID tripId, UUID userId) {
        return trips.findById(tripId).map(trip -> trip.isDrivenBy(userId)).orElse(false)
                || reservations
                        .findByTrip_IdAndPassenger_IdAndStatusIn(tripId, userId, REAL_PARTICIPANTS)
                        .isPresent();
    }

    /** The trip's audit trail, oldest first. */
    @Transactional(readOnly = true)
    public List<EventFact> events(UUID tripId) {
        return tripEvents.findByTrip_IdOrderByCreatedAtAsc(tripId).stream()
                .map(event -> new EventFact(event.getType().name(), event.getActorId(),
                        event.getCreatedAt(), event.getLat(), event.getLng()))
                .toList();
    }

    /** Every GPS fix of the trip, in the order the phone recorded them. */
    @Transactional(readOnly = true)
    public List<TrackPoint> gpsTrack(UUID tripId) {
        return gpsPoints.findByTrip_IdOrderByRecordedAtAsc(tripId).stream()
                .map(point -> new TrackPoint(point.getLat(), point.getLng(), point.getRecordedAt()))
                .toList();
    }

    /**
     * Whether a vehicle is committed to any trip that has not finished.
     *
     * <p>This is the question the vehicle module needs before letting someone delete or
     * withdraw a car: a vehicle on a scheduled or running trip must not disappear underneath it.
     */
    @Transactional(readOnly = true)
    public boolean vehicleHasUpcomingTrips(UUID vehicleId) {
        return trips.existsByVehicleIdAndStatusIn(vehicleId, TripStatus.UNFINISHED);
    }

    /** True while the user is the driver of a trip that has not finished. */
    @Transactional(readOnly = true)
    public boolean driverHasUnfinishedTrips(UUID userId) {
        return trips.existsByDriver_IdAndStatusIn(userId, TripStatus.UNFINISHED);
    }

    /** True while the user holds a pending or confirmed seat on somebody's trip. */
    @Transactional(readOnly = true)
    public boolean passengerHasActiveReservations(UUID userId) {
        return reservations.existsByPassenger_IdAndStatusIn(userId,
                Set.of(ReservationStatus.PENDING, ReservationStatus.CONFIRMED));
    }

    /**
     * How many trips each vehicle has completed, for the vehicle card's "Used in N trips".
     * A vehicle that never finished a trip is simply not in the map.
     */
    @Transactional(readOnly = true)
    public java.util.Map<UUID, Long> completedTripsByVehicle(java.util.Collection<UUID> vehicleIds) {
        if (vehicleIds.isEmpty()) return java.util.Map.of();
        java.util.Map<UUID, Long> counts = new java.util.HashMap<>();
        for (Object[] row : trips.countCompletedByVehicle(vehicleIds)) {
            counts.put((UUID) row[0], ((Number) row[1]).longValue());
        }
        return counts;
    }
}
