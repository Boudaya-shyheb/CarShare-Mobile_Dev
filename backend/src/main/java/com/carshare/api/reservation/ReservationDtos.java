package com.carshare.api.reservation;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public final class ReservationDtos {
    private ReservationDtos() { }

    public record BookRequest(@Min(1) @Max(8) int seats) { }

    public record CancelReservationRequest(@NotBlank @Size(max = 255) String reason) { }

    /**
     * The trip facts a passenger needs beside their own reservation.
     *
     * <p>Deliberately carries no seat counts. They move whenever anyone books, and the reservation
     * endpoints change them with an atomic SQL update that the already-loaded Trip entity does not
     * see — so a seat count here could be one booking out of date. Seat availability belongs to
     * the trip endpoints, which read it fresh.
     */
    public record TripBrief(UUID tripId, UUID driverId, String driverName, String originLabel,
            String destinationLabel, Instant departureTime, Instant expectedArrival,
            BigDecimal pricePerSeat, String tripStatus, Integer distanceM, Integer durationS) {
        public static TripBrief from(Trip trip) {
            return new TripBrief(trip.getId(), trip.getDriver().getId(), trip.getDriver().getFullName(),
                    trip.getOriginLabel(), trip.getDestinationLabel(), trip.getDepartureTime(),
                    trip.expectedArrival(), trip.getPricePerSeat(), trip.getStatus().name(),
                    trip.getDistanceM(), trip.getDurationS());
        }
    }

    /**
     * What the passenger who owns the reservation sees. {@code pickupCode} is filled in only once
     * the reservation is CONFIRMED, and this record is never returned to a driver.
     */
    public record ReservationDetail(UUID id, TripBrief trip, UUID passengerId, int seats,
            String status, String pickupCode, boolean lateCancellation, String cancelReason,
            Instant decidedAt, Instant cancelledAt, Instant createdAt) {
        public static ReservationDetail forPassenger(Reservation reservation) {
            boolean confirmed = reservation.getStatus().holdsConfirmedSeat();
            return new ReservationDetail(reservation.getId(), TripBrief.from(reservation.getTrip()),
                    reservation.getPassenger().getId(), reservation.getSeats(),
                    reservation.getStatus().name(),
                    confirmed ? reservation.getPickupCode() : null,
                    reservation.isLateCancellation(), reservation.getCancelReason(),
                    reservation.getDecidedAt(), reservation.getCancelledAt(),
                    reservation.getCreatedAt());
        }
    }

    /**
     * What the trip's driver sees. There is no pickup code field at all, so no change to this
     * record can ever leak one: the driver has to be told the code by the passenger.
     */
    public record PassengerView(UUID reservationId, UUID passengerId, String passengerName,
            int seats, String status, boolean lateCancellation, String cancelReason,
            Double passengerRating, long passengerRatingCount,
            Instant decidedAt, Instant cancelledAt, Instant createdAt) {
        /** Without a reputation to hand. */
        public static PassengerView from(Reservation reservation) {
            return from(reservation, null, 0L);
        }

        public static PassengerView from(Reservation reservation, Double passengerRating,
                long passengerRatingCount) {
            return new PassengerView(reservation.getId(), reservation.getPassenger().getId(),
                    reservation.getPassenger().getFullName(), reservation.getSeats(),
                    reservation.getStatus().name(), reservation.isLateCancellation(),
                    reservation.getCancelReason(), passengerRating, passengerRatingCount,
                    reservation.getDecidedAt(),
                    reservation.getCancelledAt(), reservation.getCreatedAt());
        }
    }
}
