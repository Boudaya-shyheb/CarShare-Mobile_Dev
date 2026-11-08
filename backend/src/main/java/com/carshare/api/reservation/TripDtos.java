package com.carshare.api.reservation;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Future;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public final class TripDtos {
    private TripDtos() { }

    /**
     * Coordinates are boxed so a missing JSON field fails validation instead of silently
     * becoming 0.0, which would be a valid-looking point in the Gulf of Guinea. Their ranges are
     * checked in TripService, which also rejects an origin equal to the destination.
     */
    public record PublishTripRequest(
            UUID vehicleId,
            @NotBlank @Size(max = 180) String originLabel,
            @NotNull Double originLat,
            @NotNull Double originLng,
            @NotBlank @Size(max = 180) String destinationLabel,
            @NotNull Double destinationLat,
            @NotNull Double destinationLng,
            @NotNull @Future Instant departureTime,
            @Min(1) @Max(8) int seatsTotal,
            @NotNull @DecimalMin("0.00") @DecimalMax("9999.99") BigDecimal pricePerSeat,
            boolean instantBooking,
            @Size(max = 500) String notes,
            @Min(0) Integer distanceM,
            @Min(0) Integer durationS,
            @Size(max = 20_000) String routePolyline) { }

    public record UpdateTripRequest(
            UUID vehicleId,
            @NotBlank @Size(max = 180) String originLabel,
            @NotNull Double originLat,
            @NotNull Double originLng,
            @NotBlank @Size(max = 180) String destinationLabel,
            @NotNull Double destinationLat,
            @NotNull Double destinationLng,
            @NotNull @Future Instant departureTime,
            @Min(1) @Max(8) int seatsTotal,
            @NotNull @DecimalMin("0.00") @DecimalMax("9999.99") BigDecimal pricePerSeat,
            boolean instantBooking,
            @Size(max = 500) String notes,
            @Min(0) Integer distanceM,
            @Min(0) Integer durationS,
            @Size(max = 20_000) String routePolyline) { }

    public record CancelTripRequest(@NotBlank @Size(max = 300) String reason) { }

    /** Manual transition. CANCELLED is refused here so a reason is always recorded. */
    public record ChangeStatusRequest(@NotNull TripStatus status, Double lat, Double lng) { }

    public record TripSummary(UUID id, String originLabel, String destinationLabel,
            Instant departureTime, int seatsTotal, int seatsAvailable, BigDecimal pricePerSeat,
            String status, boolean instantBooking, Integer distanceM, Integer durationS) {
        public static TripSummary from(Trip trip) {
            return new TripSummary(trip.getId(), trip.getOriginLabel(), trip.getDestinationLabel(),
                    trip.getDepartureTime(), trip.getSeatsTotal(), trip.getSeatsAvailable(),
                    trip.getPricePerSeat(), trip.getStatus().name(), trip.isInstantBooking(),
                    trip.getDistanceM(), trip.getDurationS());
        }
    }

    public record TripDetail(UUID id, UUID driverId, String driverName, UUID vehicleId,
            String originLabel, double originLat, double originLng,
            String destinationLabel, double destinationLat, double destinationLng,
            Instant departureTime, int seatsTotal, int seatsAvailable, int confirmedSeats,
            BigDecimal pricePerSeat, String status, boolean instantBooking, boolean locked,
            String notes, String cancelReason, Integer distanceM, Integer durationS,
            String routePolyline, Instant createdAt, Instant updatedAt) {
        public static TripDetail from(Trip trip) {
            return new TripDetail(trip.getId(), trip.getDriver().getId(), trip.getDriver().getFullName(),
                    trip.getVehicleId(), trip.getOriginLabel(), trip.getOriginLat(), trip.getOriginLng(),
                    trip.getDestinationLabel(), trip.getDestinationLat(), trip.getDestinationLng(),
                    trip.getDepartureTime(), trip.getSeatsTotal(), trip.getSeatsAvailable(),
                    trip.getConfirmedSeats(), trip.getPricePerSeat(), trip.getStatus().name(),
                    trip.isInstantBooking(), trip.isLocked(), trip.getNotes(), trip.getCancelReason(),
                    trip.getDistanceM(), trip.getDurationS(), trip.getRoutePolyline(),
                    trip.getCreatedAt(), trip.getUpdatedAt());
        }
    }

    /**
     * Search parameters, bound from query string values. Everything is boxed and unvalidated here
     * so TripService can answer a missing or malformed parameter with invalid_search rather than
     * Spring's generic 400 body.
     */
    public record SearchRequest(Double originLat, Double originLng, Double destinationLat,
            Double destinationLng, String departureTime, Integer seats, String sort) { }

    public record TripSearchResult(UUID tripId, UUID driverId, String driverName,
            String originLabel, String destinationLabel, Instant departureTime, int seatsAvailable,
            BigDecimal pricePerSeat, boolean instantBooking, int pickupDistanceM,
            int dropoffDistanceM, int timeGapMin, int matchScore) {
        public static TripSearchResult from(Trip trip, int pickupDistanceM, int dropoffDistanceM,
                int timeGapMin, int matchScore) {
            return new TripSearchResult(trip.getId(), trip.getDriver().getId(),
                    trip.getDriver().getFullName(), trip.getOriginLabel(), trip.getDestinationLabel(),
                    trip.getDepartureTime(), trip.getSeatsAvailable(), trip.getPricePerSeat(),
                    trip.isInstantBooking(), pickupDistanceM, dropoffDistanceM, timeGapMin, matchScore);
        }
    }

    public record EventView(UUID id, String type, UUID actorId, Double lat, Double lng,
            String detail, Instant createdAt) {
        public static EventView from(TripEvent event) {
            return new EventView(event.getId(), event.getType().name(), event.getActorId(),
                    event.getLat(), event.getLng(), event.getDetail(), event.getCreatedAt());
        }
    }
}
