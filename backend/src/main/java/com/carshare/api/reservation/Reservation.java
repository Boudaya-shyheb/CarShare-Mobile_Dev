package com.carshare.api.reservation;

import com.carshare.api.users.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/** A passenger's seat request on a published trip. */
@Entity
@Table(name = "reservations")
public class Reservation {
    @Id private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "passenger_id", nullable = false)
    private AppUser passenger;

    // SMALLINT in the migration, so the field is a short; getSeats() hands callers an int.
    @Column(nullable = false) private short seats;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private ReservationStatus status = ReservationStatus.PENDING;

    // Plain text, and CHAR(4) rather than VARCHAR, so the column matches the migration exactly.
    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "pickup_code", nullable = false, length = PickupCode.LENGTH)
    private String pickupCode;

    @Column(name = "pickup_code_attempts", nullable = false) private short pickupCodeAttempts;
    @Column(name = "late_cancellation", nullable = false) private boolean lateCancellation;
    @Column(name = "cancel_reason", length = 255) private String cancelReason;
    @Column(name = "decided_at") private Instant decidedAt;
    @Column(name = "cancelled_at") private Instant cancelledAt;
    @Column(name = "checked_in_at") private Instant checkedInAt;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at") private Instant updatedAt;

    protected Reservation() { }

    public Reservation(Trip trip, AppUser passenger, int seats, String pickupCode) {
        this.id = UUID.randomUUID();
        this.trip = trip;
        this.passenger = passenger;
        this.seats = (short) seats;
        this.pickupCode = pickupCode;
        this.createdAt = Instant.now();
    }

    /** Kept as a guard: createdAt is stamped in the constructor so a create response
     *  carries it, and this only fills in rows built some other way. */
    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }
    @PreUpdate void touch() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public Trip getTrip() { return trip; }
    public AppUser getPassenger() { return passenger; }
    public int getSeats() { return seats; }
    public ReservationStatus getStatus() { return status; }
    public String getPickupCode() { return pickupCode; }
    public int getPickupCodeAttempts() { return pickupCodeAttempts; }
    public boolean isLateCancellation() { return lateCancellation; }
    public String getCancelReason() { return cancelReason; }
    public Instant getDecidedAt() { return decidedAt; }
    public Instant getCancelledAt() { return cancelledAt; }
    public Instant getCheckedInAt() { return checkedInAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    public boolean isHeldBy(UUID passengerId) { return passenger.getId().equals(passengerId); }

    /**
     * Statuses are changed only by ReservationService, which checks the rules and writes the
     * matching trip_events row. These guards just make an illegal state unreachable.
     */
    void confirm(Instant when) {
        requireAwaitingDecision("confirmed");
        status = ReservationStatus.CONFIRMED;
        decidedAt = when;
    }

    void refuse(String reason, Instant when) {
        requireAwaitingDecision("refused");
        status = ReservationStatus.REFUSED;
        cancelReason = reason;
        decidedAt = when;
    }

    void cancel(String reason, boolean late, Instant when) {
        if (!status.isActive()) {
            throw new IllegalStateException("A " + status + " reservation cannot be cancelled.");
        }
        status = ReservationStatus.CANCELLED;
        cancelReason = reason;
        lateCancellation = late;
        cancelledAt = when;
    }

    private void requireAwaitingDecision(String what) {
        if (!status.awaitsDecision()) {
            throw new IllegalStateException("A " + status + " reservation cannot be " + what + ".");
        }
    }

    /** True once the driver has typed the right pickup code for this reservation. */
    public boolean isCheckedIn() {
        return checkedInAt != null;
    }

    /** True once the driver has used up every allowed attempt at the pickup code. */
    public boolean isPickupCodeLocked() {
        return pickupCodeAttempts >= PickupCode.MAX_ATTEMPTS;
    }

    void recordWrongPickupCode() {
        pickupCodeAttempts++;
    }

    void recordCheckIn(Instant when) {
        requireConfirmed("check in");
        checkedInAt = when;
    }

    void markNoShow(Instant when) {
        requireConfirmed("be marked a no-show");
        status = ReservationStatus.NO_SHOW;
        decidedAt = when;
    }

    void complete(Instant when) {
        requireConfirmed("be completed");
        status = ReservationStatus.COMPLETED;
        decidedAt = when;
    }

    private void requireConfirmed(String what) {
        if (!status.holdsConfirmedSeat()) {
            throw new IllegalStateException("A " + status + " reservation cannot " + what + ".");
        }
    }
}
