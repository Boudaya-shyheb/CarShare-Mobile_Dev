package com.carshare.api.reservation;

import com.carshare.api.users.AppUser;
import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "trips")
public class Trip {
    /** Assumed journey time when OSRM has not given one, used for the overlap rule. */
    public static final Duration DEFAULT_DURATION = Duration.ofHours(2);

    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false) @JoinColumn(name = "driver_id", nullable = false) private AppUser driver;
    // The Vehicles module adds the foreign key in a later migration.
    @Column(name = "vehicle_id") private UUID vehicleId;
    @Column(name = "origin_label", nullable = false, length = 180) private String originLabel;
    @Column(name = "origin_lat", nullable = false) private double originLat;
    @Column(name = "origin_lng", nullable = false) private double originLng;
    @Column(name = "destination_label", nullable = false, length = 180) private String destinationLabel;
    @Column(name = "destination_lat", nullable = false) private double destinationLat;
    @Column(name = "destination_lng", nullable = false) private double destinationLng;
    @Column(name = "departure_time", nullable = false) private Instant departureTime;
    @Column(name = "seats_total", nullable = false) private int seatsTotal;
    @Column(name = "seats_available", nullable = false) private int seatsAvailable;
    // Maintained by the reservation step; a trip with confirmed seats is locked (see isLocked).
    @Column(name = "confirmed_seats", nullable = false) private int confirmedSeats;
    @Column(name = "price_per_seat", nullable = false, precision = 8, scale = 2) private BigDecimal pricePerSeat;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private TripStatus status = TripStatus.SCHEDULED;
    @Column(name = "instant_booking", nullable = false) private boolean instantBooking;
    @Column(length = 500) private String notes;
    @Column(name = "cancel_reason", length = 300) private String cancelReason;
    @Column(name = "distance_m") private Integer distanceM;
    @Column(name = "duration_s") private Integer durationS;
    // Live tracking: the newest kept position, copied out of gps_points so the live view is
    // a single row read rather than a sort over every point.
    @Column(name = "last_lat") private Double lastLat;
    @Column(name = "last_lng") private Double lastLng;
    @Column(name = "last_position_at") private Instant lastPositionAt;
    // Google encoded polyline of the planned route. TEXT, so the JDBC type is stated
    // explicitly and ddl-auto=validate agrees with the migration.
    @JdbcTypeCode(SqlTypes.LONGVARCHAR)
    @Column(name = "route_polyline") private String routePolyline;
    @Column(nullable = false) private boolean deviating;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at") private Instant updatedAt;

    protected Trip() { }

    public Trip(AppUser driver, UUID vehicleId, String originLabel, double originLat, double originLng,
            String destinationLabel, double destinationLat, double destinationLng, Instant departureTime,
            int seatsTotal, BigDecimal pricePerSeat, boolean instantBooking, String notes,
            Integer distanceM, Integer durationS, String routePolyline) {
        this.id = UUID.randomUUID();
        this.driver = driver;
        this.vehicleId = vehicleId;
        this.originLabel = originLabel;
        this.originLat = originLat;
        this.originLng = originLng;
        this.destinationLabel = destinationLabel;
        this.destinationLat = destinationLat;
        this.destinationLng = destinationLng;
        this.departureTime = departureTime;
        this.seatsTotal = seatsTotal;
        this.seatsAvailable = seatsTotal;
        this.pricePerSeat = pricePerSeat;
        this.instantBooking = instantBooking;
        this.notes = notes;
        this.distanceM = distanceM;
        this.durationS = durationS;
        this.routePolyline = routePolyline;
    }

    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }
    @PreUpdate void touch() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public AppUser getDriver() { return driver; }
    public UUID getVehicleId() { return vehicleId; }
    public String getOriginLabel() { return originLabel; }
    public double getOriginLat() { return originLat; }
    public double getOriginLng() { return originLng; }
    public String getDestinationLabel() { return destinationLabel; }
    public double getDestinationLat() { return destinationLat; }
    public double getDestinationLng() { return destinationLng; }
    public Instant getDepartureTime() { return departureTime; }
    public int getSeatsTotal() { return seatsTotal; }
    public int getSeatsAvailable() { return seatsAvailable; }
    public int getConfirmedSeats() { return confirmedSeats; }
    public BigDecimal getPricePerSeat() { return pricePerSeat; }
    public TripStatus getStatus() { return status; }
    public boolean isInstantBooking() { return instantBooking; }
    public String getNotes() { return notes; }
    public String getCancelReason() { return cancelReason; }
    public Integer getDistanceM() { return distanceM; }
    public Integer getDurationS() { return durationS; }
    public Double getLastLat() { return lastLat; }
    public Double getLastLng() { return lastLng; }
    public Instant getLastPositionAt() { return lastPositionAt; }
    public String getRoutePolyline() { return routePolyline; }
    public boolean isDeviating() { return deviating; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    /** A trip holding confirmed reservations may no longer change its time, route or price. */
    public boolean isLocked() { return confirmedSeats > 0; }

    public boolean isDrivenBy(UUID userId) { return driver.getId().equals(userId); }

    /**
     * Applies a status change. Callers go through TripService.changeStatus so the matching
     * TripEvent is written; this guard only makes an illegal state unreachable.
     */
    void applyStatus(TripStatus next) {
        if (!status.canMoveTo(next)) {
            throw new IllegalStateException("A trip cannot move from " + status + " to " + next + ".");
        }
        status = next;
    }

    void cancel(String reason) {
        applyStatus(TripStatus.CANCELLED);
        cancelReason = reason;
        seatsAvailable = seatsTotal;
        confirmedSeats = 0;
    }

    /** Editable while the trip is scheduled; the service decides which fields may change. */
    void updateDetails(UUID vehicleId, String originLabel, double originLat, double originLng,
            String destinationLabel, double destinationLat, double destinationLng, Instant departureTime,
            int seatsTotal, BigDecimal pricePerSeat, boolean instantBooking, String notes,
            Integer distanceM, Integer durationS, String routePolyline) {
        int heldSeats = this.seatsTotal - this.seatsAvailable;
        this.vehicleId = vehicleId;
        this.originLabel = originLabel;
        this.originLat = originLat;
        this.originLng = originLng;
        this.destinationLabel = destinationLabel;
        this.destinationLat = destinationLat;
        this.destinationLng = destinationLng;
        this.departureTime = departureTime;
        this.seatsTotal = seatsTotal;
        this.seatsAvailable = seatsTotal - heldSeats;
        this.pricePerSeat = pricePerSeat;
        this.instantBooking = instantBooking;
        this.notes = notes;
        this.distanceM = distanceM;
        this.durationS = durationS;
        this.routePolyline = routePolyline;
    }

    /**
     * Adjusts the confirmed seat count in memory. Production code changes seat counts through the
     * atomic updates on TripRepository instead, so two bookings can never lose each other's
     * change; this stays for building a locked trip in tests.
     */
    void recordConfirmedSeats(int delta) {
        confirmedSeats += delta;
        if (confirmedSeats < 0) confirmedSeats = 0;
    }

    /** How long this trip is expected to take; two hours when no route duration is known. */
    public Duration expectedDuration() {
        return durationS == null ? DEFAULT_DURATION : Duration.ofSeconds(durationS);
    }

    /** The end of the window this trip occupies in a passenger's diary. */
    public Instant expectedArrival() {
        return departureTime.plus(expectedDuration());
    }

    /**
     * True when the two trips' [departure, expected arrival) windows intersect. Trips that merely
     * touch — one arriving exactly as the other leaves — do not overlap.
     */
    public boolean overlaps(Trip other) {
        return departureTime.isBefore(other.expectedArrival())
                && other.getDepartureTime().isBefore(expectedArrival());
    }

    /** Remembers the newest kept GPS fix. The service decides which points are worth keeping. */
    void recordPosition(double lat, double lng, Instant recordedAt) {
        lastLat = lat;
        lastLng = lng;
        lastPositionAt = recordedAt;
    }

    void markDeviating(boolean value) {
        deviating = value;
    }

    /** Where the driver is heading now: the pickup point, or the drop-off once aboard. */
    public double targetLat() {
        return status.trackingTarget() == TrackingTarget.PICKUP ? originLat : destinationLat;
    }

    public double targetLng() {
        return status.trackingTarget() == TrackingTarget.PICKUP ? originLng : destinationLng;
    }

    public boolean hasKnownPosition() {
        return lastLat != null && lastLng != null;
    }
}
