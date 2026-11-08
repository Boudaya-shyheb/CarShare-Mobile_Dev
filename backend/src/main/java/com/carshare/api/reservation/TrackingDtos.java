package com.carshare.api.reservation;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public final class TrackingDtos {
    private TrackingDtos() { }

    /**
     * One GPS fix. Everything is boxed and unannotated so TrackingService can answer a missing or
     * impossible value with invalid_positions rather than the generic validation_error body.
     */
    public record PositionPoint(Double lat, Double lng, Float speedMps, Instant recordedAt) { }

    /**
     * A batch of fixes. The app sends one point while it is online and flushes a whole buffer
     * after a dead spot, which is why this takes a list rather than a single point.
     */
    public record ReportPositionsRequest(List<PositionPoint> points) { }

    public record CheckInRequest(@NotBlank @Size(max = 8) String code) { }

    /**
     * What the live tracking screen polls every five seconds.
     *
     * <p>{@code myReservationStatus} and {@code checkedIn} are filled in only for a passenger
     * looking at their own trip; they are null for the driver, who sees the whole passenger list
     * through the trip's reservation endpoint instead.
     */
    public record LiveView(String tripStatus, Double lastLat, Double lastLng,
            Instant lastPositionAt, String target, Integer distanceToTargetM, Integer etaSeconds,
            boolean deviating, String myReservationStatus, Boolean checkedIn) { }
}
