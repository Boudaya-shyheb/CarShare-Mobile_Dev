package com.carshare.api.reservation;

import com.carshare.api.users.AppUser;
import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "trips")
public class Trip {
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
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at") private Instant updatedAt;

    protected Trip() { }

    public Trip(AppUser driver, UUID vehicleId, String originLabel, double originLat, double originLng,
            String destinationLabel, double destinationLat, double destinationLng, Instant departureTime,
            int seatsTotal, BigDecimal pricePerSeat, boolean instantBooking, String notes,
            Integer distanceM, Integer durationS) {
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
            Integer distanceM, Integer durationS) {
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
    }

    /** Called by the reservation step when seats are confirmed or released. */
    void recordConfirmedSeats(int delta) {
        confirmedSeats += delta;
        if (confirmedSeats < 0) confirmedSeats = 0;
    }
}
