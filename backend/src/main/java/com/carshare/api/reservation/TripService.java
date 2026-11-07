package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TripService {
    /** Statuses a trip passes through before it is finished; drives the "upcoming" tab. */
    private static final Set<TripStatus> ACTIVE_STATUSES = Set.of(TripStatus.SCHEDULED,
            TripStatus.DRIVER_EN_ROUTE, TripStatus.DRIVER_ARRIVED, TripStatus.PICKED_UP,
            TripStatus.IN_PROGRESS);

    /** How far either end of a trip may be from what the passenger asked for. */
    private static final double SEARCH_RADIUS_M = MatchScorer.MAX_DISTANCE_M;
    /** Only trips leaving within this much of the requested time are considered. */
    private static final Duration SEARCH_TIME_WINDOW = Duration.ofHours(3);
    private static final int MAX_SEARCH_RESULTS = 50;
    private static final int MAX_SEATS = 8;

    private final TripRepository trips;
    private final TripEventRepository tripEvents;
    private final UserRepository users;

    public TripService(TripRepository trips, TripEventRepository tripEvents, UserRepository users) {
        this.trips = trips;
        this.tripEvents = tripEvents;
        this.users = users;
    }

    @Transactional
    public TripDtos.TripDetail publish(UUID driverId, TripDtos.PublishTripRequest request) {
        AppUser driver = requirePublishingDriver(driverId);
        validateItinerary(request.originLat(), request.originLng(),
                request.destinationLat(), request.destinationLng());
        Trip trip = new Trip(driver, request.vehicleId(), request.originLabel().trim(),
                request.originLat(), request.originLng(), request.destinationLabel().trim(),
                request.destinationLat(), request.destinationLng(), request.departureTime(),
                request.seatsTotal(), request.pricePerSeat(), request.instantBooking(),
                clean(request.notes()), request.distanceM(), request.durationS());
        trips.save(trip);
        // Publishing is not a transition, so it records its event directly. Every later status
        // change goes through changeStatus.
        tripEvents.save(new TripEvent(trip, TripEventType.PUBLISHED, driverId,
                request.originLat(), request.originLng(), null));
        return TripDtos.TripDetail.from(trip);
    }

    @Transactional(readOnly = true)
    public List<TripDtos.TripSummary> listMine(UUID driverId, String scope) {
        String wanted = scope == null || scope.isBlank() ? "all" : scope.trim().toLowerCase(Locale.ROOT);
        List<Trip> found = switch (wanted) {
            case "all" -> trips.findByDriver_IdOrderByDepartureTimeDesc(driverId);
            case "upcoming" -> trips.findByDriver_IdAndStatusInOrderByDepartureTimeDesc(driverId, ACTIVE_STATUSES);
            case "past" -> trips.findByDriver_IdAndStatusInOrderByDepartureTimeDesc(driverId, Set.of(TripStatus.COMPLETED));
            case "cancelled" -> trips.findByDriver_IdAndStatusInOrderByDepartureTimeDesc(driverId, Set.of(TripStatus.CANCELLED));
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_trip_scope",
                    "Choose upcoming, past, or cancelled.");
        };
        return found.stream().map(TripDtos.TripSummary::from).toList();
    }

    @Transactional(readOnly = true)
    public TripDtos.TripDetail get(UUID tripId) {
        return TripDtos.TripDetail.from(trips.findById(tripId)
                .orElseThrow(TripService::tripNotFound));
    }

    @Transactional(readOnly = true)
    public List<TripDtos.EventView> listEvents(UUID driverId, UUID tripId) {
        // TODO(step 5): also allow passengers holding a CONFIRMED reservation on this trip.
        requireOwnedTrip(driverId, tripId);
        return tripEvents.findByTrip_IdOrderByCreatedAtAsc(tripId).stream()
                .map(TripDtos.EventView::from).toList();
    }

    @Transactional
    public TripDtos.TripDetail update(UUID driverId, UUID tripId, TripDtos.UpdateTripRequest request) {
        Trip trip = requireOwnedTrip(driverId, tripId);
        if (trip.getStatus() != TripStatus.SCHEDULED) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_not_editable",
                    "A trip can only be changed while it is still scheduled.");
        }
        validateItinerary(request.originLat(), request.originLng(),
                request.destinationLat(), request.destinationLng());
        if (trip.isLocked() && changesFrozenFields(trip, request)) {
            throw new ApiException(HttpStatus.CONFLICT, "trip_locked",
                    "This trip already has a confirmed reservation, so its time, route, and price can no longer change.");
        }
        if (request.seatsTotal() < trip.getConfirmedSeats()) {
            throw new ApiException(HttpStatus.CONFLICT, "seats_below_reserved",
                    "Passengers already hold " + trip.getConfirmedSeats() + " seats on this trip.");
        }
        trip.updateDetails(request.vehicleId(), request.originLabel().trim(), request.originLat(),
                request.originLng(), request.destinationLabel().trim(), request.destinationLat(),
                request.destinationLng(), request.departureTime(), request.seatsTotal(),
                request.pricePerSeat(), request.instantBooking(), clean(request.notes()),
                request.distanceM(), request.durationS());
        tripEvents.save(new TripEvent(trip, TripEventType.UPDATED, driverId, null, null, null));
        return TripDtos.TripDetail.from(trip);
    }

    @Transactional
    public TripDtos.TripDetail cancel(UUID driverId, UUID tripId, String reason) {
        Trip trip = requireOwnedTrip(driverId, tripId);
        return TripDtos.TripDetail.from(
                changeStatus(trip, TripStatus.CANCELLED, driverId, null, null, reason.trim()));
    }

    @Transactional
    public TripDtos.TripDetail changeStatus(UUID driverId, UUID tripId, TripDtos.ChangeStatusRequest request) {
        if (request.status() == TripStatus.CANCELLED) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "cancel_reason_required",
                    "Cancel a trip through the cancel endpoint so a reason is recorded.");
        }
        Trip trip = requireOwnedTrip(driverId, tripId);
        if (request.lat() != null && request.lng() != null) {
            validatePoint(request.lat(), request.lng(), "position");
        }
        return TripDtos.TripDetail.from(
                changeStatus(trip, request.status(), driverId, request.lat(), request.lng(), null));
    }

    /**
     * The one method allowed to move a trip between statuses. It checks
     * {@link TripStatus#allowedNext()} and writes the matching {@link TripEvent} row. Later steps
     * (geofence arrival, check-in, completion) call it instead of touching the status themselves.
     */
    Trip changeStatus(Trip trip, TripStatus next, UUID actorId, Double lat, Double lng, String detail) {
        if (!trip.getStatus().canMoveTo(next)) {
            throw new ApiException(HttpStatus.CONFLICT, "invalid_trip_transition",
                    "This trip is " + label(trip.getStatus()) + ", so it cannot move to "
                            + label(next) + ".");
        }
        if (next == TripStatus.CANCELLED) {
            trip.cancel(detail);
        } else {
            trip.applyStatus(next);
        }
        tripEvents.save(new TripEvent(trip, TripEventType.forStatus(next), actorId, lat, lng, detail));
        return trip;
    }

    @Transactional(readOnly = true)
    public List<TripDtos.TripSearchResult> search(UUID searcherId, TripDtos.SearchRequest request) {
        double originLat = requiredCoordinate(request.originLat(), "originLat");
        double originLng = requiredCoordinate(request.originLng(), "originLng");
        double destinationLat = requiredCoordinate(request.destinationLat(), "destinationLat");
        double destinationLng = requiredCoordinate(request.destinationLng(), "destinationLng");
        validateItinerary(originLat, originLng, destinationLat, destinationLng);

        Instant wantedDeparture = parseDepartureTime(request.departureTime());
        int seats = request.seats() == null ? 1 : request.seats();
        if (seats < 1 || seats > MAX_SEATS) {
            throw invalidSearch("Choose between 1 and " + MAX_SEATS + " seats.");
        }
        TripSortOrder sort = TripSortOrder.fromParameter(request.sort());

        Instant now = Instant.now();
        double latDelta = GeoUtils.latitudeDelta(SEARCH_RADIUS_M);
        List<Trip> candidates = trips.searchCandidates(TripStatus.SCHEDULED, now,
                wantedDeparture.minus(SEARCH_TIME_WINDOW), wantedDeparture.plus(SEARCH_TIME_WINDOW),
                seats, searcherId,
                originLat - latDelta, originLat + latDelta,
                originLng - GeoUtils.longitudeDelta(SEARCH_RADIUS_M, originLat),
                originLng + GeoUtils.longitudeDelta(SEARCH_RADIUS_M, originLat),
                destinationLat - latDelta, destinationLat + latDelta,
                destinationLng - GeoUtils.longitudeDelta(SEARCH_RADIUS_M, destinationLat),
                destinationLng + GeoUtils.longitudeDelta(SEARCH_RADIUS_M, destinationLat));

        List<TripDtos.TripSearchResult> matches = new ArrayList<>();
        for (Trip trip : candidates) {
            // The query already applies these, but a passenger must never be shown their own trip
            // or a trip that cannot take them, so the rules are re-checked on the loaded row.
            if (!isSearchable(trip, searcherId, seats, now)) continue;

            double pickupDistance = GeoUtils.haversineMetres(originLat, originLng,
                    trip.getOriginLat(), trip.getOriginLng());
            if (pickupDistance > SEARCH_RADIUS_M) continue;
            double dropoffDistance = GeoUtils.haversineMetres(destinationLat, destinationLng,
                    trip.getDestinationLat(), trip.getDestinationLng());
            if (dropoffDistance > SEARCH_RADIUS_M) continue;

            long timeGapMin = Math.abs(
                    Duration.between(wantedDeparture, trip.getDepartureTime()).toMinutes());
            int score = MatchScorer.score(pickupDistance, dropoffDistance, timeGapMin,
                    trip.getDriver().getId());
            if (!MatchScorer.isMatch(score)) continue;

            matches.add(TripDtos.TripSearchResult.from(trip, (int) Math.round(pickupDistance),
                    (int) Math.round(dropoffDistance), (int) timeGapMin, score));
        }
        matches.sort(sort.comparator());
        return List.copyOf(matches.subList(0, Math.min(matches.size(), MAX_SEARCH_RESULTS)));
    }

    private boolean isSearchable(Trip trip, UUID searcherId, int seats, Instant now) {
        return trip.getStatus().acceptsReservations()
                && !trip.isDrivenBy(searcherId)
                && trip.getSeatsAvailable() >= seats
                && trip.getDepartureTime().isAfter(now);
    }

    private Instant parseDepartureTime(String value) {
        if (value == null || value.isBlank()) {
            throw invalidSearch("Tell us when you want to leave.");
        }
        try {
            return Instant.parse(value.trim());
        } catch (java.time.format.DateTimeParseException invalid) {
            throw invalidSearch("The departure time must be an ISO instant, such as 2026-11-08T07:30:00Z.");
        }
    }

    private double requiredCoordinate(Double value, String name) {
        if (value == null) {
            throw invalidSearch("The search is missing " + name + ".");
        }
        return value;
    }

    private static ApiException invalidSearch(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "invalid_search", message);
    }

    private AppUser requirePublishingDriver(UUID userId) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "account_not_found", "Your account could not be found."));
        if (user.getRole() != UserRole.DRIVER) {
            throw new ApiException(HttpStatus.FORBIDDEN, "driver_role_required",
                    "Only a driver account can publish a trip.");
        }
        if (user.getAccountStatus() == UserStatus.SUSPENDED || user.getAccountStatus() == UserStatus.BANNED) {
            throw new ApiException(HttpStatus.FORBIDDEN, "account_restricted",
                    "Your account is restricted, so you cannot publish a trip.");
        }
        return user;
    }

    // 404 rather than 403, so one driver cannot probe another driver's trip ids.
    private Trip requireOwnedTrip(UUID driverId, UUID tripId) {
        return trips.findByIdAndDriver_Id(tripId, driverId).orElseThrow(TripService::tripNotFound);
    }

    private static ApiException tripNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "trip_not_found", "This trip could not be found.");
    }

    private boolean changesFrozenFields(Trip trip, TripDtos.UpdateTripRequest request) {
        return !trip.getDepartureTime().equals(request.departureTime())
                || trip.getPricePerSeat().compareTo(request.pricePerSeat()) != 0
                || !trip.getOriginLabel().equals(request.originLabel().trim())
                || !trip.getDestinationLabel().equals(request.destinationLabel().trim())
                || trip.getOriginLat() != request.originLat()
                || trip.getOriginLng() != request.originLng()
                || trip.getDestinationLat() != request.destinationLat()
                || trip.getDestinationLng() != request.destinationLng();
    }

    private void validateItinerary(double originLat, double originLng,
            double destinationLat, double destinationLng) {
        validatePoint(originLat, originLng, "pickup point");
        validatePoint(destinationLat, destinationLng, "drop-off point");
        if (originLat == destinationLat && originLng == destinationLng) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "same_origin_and_destination",
                    "Choose a drop-off point different from the pickup point.");
        }
    }

    private void validatePoint(double lat, double lng, String what) {
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_coordinates",
                    "The " + what + " is not a valid location.");
        }
    }

    private static String clean(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static String label(TripStatus status) {
        return status.name().toLowerCase(Locale.ROOT).replace('_', ' ');
    }
}
