package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Live tracking: the driver's positions, the geofences that move the trip along on their own,
 * pickup check-in, no-shows and the route deviation alert.
 *
 * <p>Every status change goes through {@link TripService#changeStatus}, so the transition table
 * and the trip_events audit row stay in one place.
 */
@Service
public class TrackingService {
    /** How close to either end of the route counts as having arrived. */
    static final double GEOFENCE_RADIUS_M = 100d;

    /** How far off the planned route raises the deviation alert. */
    static final double DEVIATION_THRESHOLD_M = 300d;

    /** One request may flush this many buffered points. */
    static final int MAX_POINTS_PER_REQUEST = 50;

    /** Points closer together than this are dropped, so a parked phone cannot flood the table. */
    static final Duration MIN_POSITION_GAP = Duration.ofSeconds(2);

    /** How long the driver must wait at the pickup point before a no-show is allowed. */
    static final Duration NO_SHOW_GRACE = Duration.ofMinutes(5);

    /** ETA speed floor, about 30 km/h, so a stopped car still gives a usable estimate. */
    static final double MIN_ETA_SPEED_MPS = 8.3d;

    static final String GEOFENCE_DETAIL = "geofence";
    static final String ALL_ABOARD_DETAIL = "all_passengers_checked_in";

    private static final Set<ReservationStatus> CONFIRMED_ONLY =
            Set.of(ReservationStatus.CONFIRMED);

    /**
     * Who may watch a trip's position. COMPLETED is included so the drop-off geofence, which
     * completes the trip and the reservation in the same request, still lets the passenger's next
     * poll land on the finished state instead of a 404.
     */
    private static final Set<ReservationStatus> MAY_WATCH =
            Set.of(ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED);

    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final GpsPointRepository gpsPoints;
    private final TripEventRepository tripEvents;
    private final TripService tripService;
    private final Clock clock;

    public TrackingService(TripRepository trips, ReservationRepository reservations,
            GpsPointRepository gpsPoints, TripEventRepository tripEvents, TripService tripService,
            Clock clock) {
        this.trips = trips;
        this.reservations = reservations;
        this.gpsPoints = gpsPoints;
        this.tripEvents = tripEvents;
        this.tripService = tripService;
        this.clock = clock;
    }

    // --- positions ---------------------------------------------------------------------------

    @Transactional
    public TrackingDtos.LiveView reportPositions(UUID driverId, UUID tripId,
            TrackingDtos.ReportPositionsRequest request) {
        Trip trip = trips.findByIdAndDriver_Id(tripId, driverId)
                .orElseThrow(TrackingService::tripNotFound);
        if (!trip.getStatus().acceptsPositions()) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_tracking",
                    "This trip is " + label(trip.getStatus()) + ", so it is not being tracked.");
        }
        List<TrackingDtos.PositionPoint> points = validate(request);

        // A point is kept only if it is at least MIN_POSITION_GAP newer than the last one kept,
        // which covers both rules at once: anything at or before the trip's last known position
        // is already too old, and anything bunched up behind a kept point is dropped.
        Instant lastKept = trip.getLastPositionAt();
        List<GpsPoint> keeping = new ArrayList<>();
        for (TrackingDtos.PositionPoint point : points) {
            if (lastKept != null && point.recordedAt().isBefore(lastKept.plus(MIN_POSITION_GAP))) {
                continue;
            }
            keeping.add(new GpsPoint(trip, point.lat(), point.lng(), point.speedMps(),
                    point.recordedAt()));
            lastKept = point.recordedAt();
        }
        if (!keeping.isEmpty()) {
            gpsPoints.saveAll(keeping);
            // Each kept point is the newest position at its moment, so the geofences and the
            // deviation check run per point. That matters when the app flushes a buffer that
            // crosses a geofence part-way through.
            for (GpsPoint kept : keeping) {
                trip.recordPosition(kept.getLat(), kept.getLng(), kept.getRecordedAt());
                applyAutomaticTransitions(trip, driverId, kept);
            }
        }
        return liveView(trip, null);
    }

    // --- the live view -----------------------------------------------------------------------

    @Transactional(readOnly = true)
    public TrackingDtos.LiveView live(UUID viewerId, UUID tripId) {
        Trip trip = trips.findById(tripId).orElseThrow(TrackingService::tripNotFound);
        if (trip.isDrivenBy(viewerId)) {
            return liveView(trip, null);
        }
        // 404 rather than 403: someone with no seat on this trip is not told it exists.
        Reservation mine = reservations
                .findByTrip_IdAndPassenger_IdAndStatusIn(tripId, viewerId, MAY_WATCH)
                .orElseThrow(TrackingService::tripNotFound);
        return liveView(trip, mine);
    }

    // --- pickup check-in ---------------------------------------------------------------------

    /**
     * A wrong code has to be remembered, so an ApiException must not roll the attempt back. Same
     * reasoning as the failed sign-in counter in the auth module.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public ReservationDtos.PassengerView checkIn(UUID driverId, UUID reservationId, String code) {
        Instant now = clock.instant();
        Reservation reservation = requireReservationOnOwnTrip(driverId, reservationId);
        Trip trip = reservation.getTrip();
        requireArrived(trip);
        requireConfirmedSeat(reservation, "checked in");
        if (reservation.isCheckedIn()) {
            throw new ApiException(HttpStatus.CONFLICT, "already_checked_in",
                    "This passenger is already aboard.");
        }
        if (reservation.isPickupCodeLocked()) {
            throw pickupCodeLocked();
        }
        if (!reservation.getPickupCode().equals(code == null ? null : code.trim())) {
            reservation.recordWrongPickupCode();
            if (reservation.isPickupCodeLocked()) {
                tripEvents.save(new TripEvent(trip, TripEventType.CHECK_IN_FAILED, driverId,
                        trip.getLastLat(), trip.getLastLng(), "pickup_code_locked"));
                throw pickupCodeLocked();
            }
            int left = PickupCode.MAX_ATTEMPTS - reservation.getPickupCodeAttempts();
            throw new ApiException(HttpStatus.BAD_REQUEST, "wrong_pickup_code",
                    "That code is not right. " + left + (left == 1 ? " try" : " tries") + " left.");
        }
        reservation.recordCheckIn(now);
        tripEvents.save(new TripEvent(trip, TripEventType.CHECK_IN, driverId, trip.getLastLat(),
                trip.getLastLng(), null));
        moveToPickedUpIfEveryoneIsSettled(trip, driverId);
        return ReservationDtos.PassengerView.from(reservation);
    }

    // --- no-show ----------------------------------------------------------------------------

    @Transactional
    public ReservationDtos.PassengerView markNoShow(UUID driverId, UUID reservationId) {
        Instant now = clock.instant();
        Reservation reservation = requireReservationOnOwnTrip(driverId, reservationId);
        Trip trip = reservation.getTrip();
        requireArrived(trip);
        requireConfirmedSeat(reservation, "marked a no-show");
        if (reservation.isCheckedIn()) {
            throw new ApiException(HttpStatus.CONFLICT, "already_checked_in",
                    "This passenger is already aboard.");
        }
        requireGraceHasPassed(trip, now);

        reservation.markNoShow(now);
        // The seat was confirmed, so both counts come back.
        trips.releaseSeats(trip.getId(), reservation.getSeats());
        trips.releaseConfirmedSeats(trip.getId(), reservation.getSeats());
        tripEvents.save(new TripEvent(trip, TripEventType.NO_SHOW, driverId, trip.getLastLat(),
                trip.getLastLng(), null));
        // This may have been the last passenger the driver was waiting for.
        moveToPickedUpIfEveryoneIsSettled(trip, driverId);
        return ReservationDtos.PassengerView.from(reservation);
    }

    // --- the automatic parts -----------------------------------------------------------------

    private void applyAutomaticTransitions(Trip trip, UUID driverId, GpsPoint point) {
        if (trip.getStatus() == TripStatus.DRIVER_EN_ROUTE
                && within(point, trip.getOriginLat(), trip.getOriginLng())) {
            tripService.changeStatus(trip, TripStatus.DRIVER_ARRIVED, driverId, point.getLat(),
                    point.getLng(), GEOFENCE_DETAIL);
            return;
        }
        if (trip.getStatus() != TripStatus.IN_PROGRESS) {
            return;
        }
        if (within(point, trip.getDestinationLat(), trip.getDestinationLng())) {
            tripService.changeStatus(trip, TripStatus.COMPLETED, driverId, point.getLat(),
                    point.getLng(), GEOFENCE_DETAIL);
            completeEveryoneAboard(trip);
            return;
        }
        checkDeviation(trip, driverId, point);
    }

    private void checkDeviation(Trip trip, UUID driverId, GpsPoint point) {
        List<double[]> route = GeoUtils.decodePolyline(trip.getRoutePolyline());
        if (route.isEmpty()) {
            return; // No planned route to compare against.
        }
        double offRoute = GeoUtils.distanceToPolylineMetres(point.getLat(), point.getLng(), route);
        if (Double.isNaN(offRoute)) {
            return;
        }
        boolean nowDeviating = offRoute > DEVIATION_THRESHOLD_M;
        if (nowDeviating == trip.isDeviating()) {
            return; // Nothing changed, so no second alert.
        }
        trip.markDeviating(nowDeviating);
        tripEvents.save(new TripEvent(trip,
                nowDeviating ? TripEventType.DEVIATION : TripEventType.DEVIATION_RESOLVED,
                driverId, point.getLat(), point.getLng(), Math.round(offRoute) + " m off route"));
    }

    /**
     * Moves a waiting trip to PICKED_UP once every confirmed passenger is either aboard or marked
     * a no-show, provided at least one is actually aboard. The driver then starts the ride with
     * the status endpoint.
     */
    private void moveToPickedUpIfEveryoneIsSettled(Trip trip, UUID driverId) {
        if (trip.getStatus() != TripStatus.DRIVER_ARRIVED) {
            return;
        }
        // No-shows are no longer CONFIRMED, so they drop out of this list on their own.
        List<Reservation> stillConfirmed =
                reservations.findByTrip_IdAndStatusIn(trip.getId(), CONFIRMED_ONLY);
        long aboard = stillConfirmed.stream().filter(Reservation::isCheckedIn).count();
        if (aboard == 0 || aboard < stillConfirmed.size()) {
            return;
        }
        tripService.changeStatus(trip, TripStatus.PICKED_UP, driverId, trip.getLastLat(),
                trip.getLastLng(), ALL_ABOARD_DETAIL);
    }

    private void completeEveryoneAboard(Trip trip) {
        Instant now = clock.instant();
        for (Reservation reservation
                : reservations.findByTrip_IdAndStatusIn(trip.getId(), CONFIRMED_ONLY)) {
            if (reservation.isCheckedIn()) {
                reservation.complete(now);
            }
        }
    }

    // --- helpers ----------------------------------------------------------------------------

    private boolean within(GpsPoint point, double lat, double lng) {
        return GeoUtils.haversineMetres(point.getLat(), point.getLng(), lat, lng)
                <= GEOFENCE_RADIUS_M;
    }

    private TrackingDtos.LiveView liveView(Trip trip, Reservation mine) {
        Integer distance = null;
        Integer eta = null;
        if (trip.hasKnownPosition()) {
            double metres = GeoUtils.haversineMetres(trip.getLastLat(), trip.getLastLng(),
                    trip.targetLat(), trip.targetLng());
            distance = (int) Math.round(metres);
            eta = (int) Math.round(metres / Math.max(lastKnownSpeed(trip), MIN_ETA_SPEED_MPS));
        }
        return new TrackingDtos.LiveView(trip.getStatus().name(), trip.getLastLat(),
                trip.getLastLng(), trip.getLastPositionAt(), trip.getStatus().trackingTarget().name(),
                distance, eta, trip.isDeviating(),
                mine == null ? null : mine.getStatus().name(),
                mine == null ? null : mine.isCheckedIn());
    }

    private double lastKnownSpeed(Trip trip) {
        return gpsPoints.findFirstByTrip_IdOrderByRecordedAtDesc(trip.getId())
                .map(GpsPoint::getSpeedMps)
                .filter(Objects::nonNull)
                .map(Float::doubleValue)
                .orElse(0d);
    }

    private List<TrackingDtos.PositionPoint> validate(TrackingDtos.ReportPositionsRequest request) {
        List<TrackingDtos.PositionPoint> points = request == null ? null : request.points();
        if (points == null || points.isEmpty()) {
            throw invalidPositions("Send at least one position.");
        }
        if (points.size() > MAX_POINTS_PER_REQUEST) {
            throw invalidPositions("Send at most " + MAX_POINTS_PER_REQUEST + " positions at a time.");
        }
        for (TrackingDtos.PositionPoint point : points) {
            if (point == null || point.lat() == null || point.lng() == null
                    || point.recordedAt() == null) {
                throw invalidPositions("Every position needs a latitude, longitude, and time.");
            }
            if (point.lat() < -90 || point.lat() > 90 || point.lng() < -180 || point.lng() > 180) {
                throw invalidPositions("One of those positions is not a valid location.");
            }
            if (point.speedMps() != null && point.speedMps() < 0) {
                throw invalidPositions("A speed cannot be negative.");
            }
        }
        // The app buffers while offline, so the batch is sorted here rather than trusted.
        return points.stream()
                .sorted(Comparator.comparing(TrackingDtos.PositionPoint::recordedAt))
                .toList();
    }

    private void requireArrived(Trip trip) {
        if (trip.getStatus() != TripStatus.DRIVER_ARRIVED) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_tracking",
                    "This trip is " + label(trip.getStatus())
                            + ", so nobody can be checked in or marked a no-show.");
        }
    }

    private void requireGraceHasPassed(Trip trip, Instant now) {
        Instant arrivedAt = tripEvents
                .findFirstByTrip_IdAndTypeOrderByCreatedAtDesc(trip.getId(),
                        TripEventType.DRIVER_ARRIVED)
                .map(TripEvent::getCreatedAt)
                .orElse(null);
        // With no arrival on record there is nothing to measure the wait from, so it is too early.
        if (arrivedAt == null || Duration.between(arrivedAt, now).compareTo(NO_SHOW_GRACE) < 0) {
            throw new ApiException(HttpStatus.CONFLICT, "no_show_too_early",
                    "Wait " + NO_SHOW_GRACE.toMinutes()
                            + " minutes at the pickup point before marking a no-show.");
        }
    }

    private void requireConfirmedSeat(Reservation reservation, String what) {
        if (!reservation.getStatus().holdsConfirmedSeat()) {
            throw new ApiException(HttpStatus.CONFLICT, "invalid_reservation_state",
                    "This reservation is " + label(reservation.getStatus())
                            + ", so it cannot be " + what + ".");
        }
    }

    // 404 rather than 403, matching the trip endpoints, so these routes cannot be used to find
    // out which trips belong to another driver.
    private Reservation requireReservationOnOwnTrip(UUID driverId, UUID reservationId) {
        Reservation reservation = reservations.findById(reservationId)
                .orElseThrow(TrackingService::reservationNotFound);
        if (!reservation.getTrip().isDrivenBy(driverId)) {
            throw tripNotFound();
        }
        return reservation;
    }

    private static ApiException invalidPositions(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "invalid_positions", message);
    }

    private static ApiException pickupCodeLocked() {
        return new ApiException(HttpStatus.CONFLICT, "pickup_code_locked",
                "Too many wrong codes. Ask the passenger to show their reservation instead.");
    }

    private static ApiException reservationNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "reservation_not_found",
                "This reservation could not be found.");
    }

    private static ApiException tripNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "trip_not_found",
                "This trip could not be found.");
    }

    private static String label(TripStatus status) {
        return status.name().toLowerCase(Locale.ROOT).replace('_', ' ');
    }

    private static String label(ReservationStatus status) {
        return status.name().toLowerCase(Locale.ROOT).replace('_', ' ');
    }
}
