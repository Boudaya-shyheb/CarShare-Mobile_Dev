package com.carshare.api.reservation;

import java.util.Set;

/**
 * Lifecycle of a published trip.
 *
 * <p>{@link #allowedNext()} is the single source of truth for the state machine. Every status
 * change goes through {@code TripService.changeStatus}, which checks this transition table and
 * writes a {@link TripEvent} row.
 */
public enum TripStatus {
    SCHEDULED,
    DRIVER_EN_ROUTE,
    DRIVER_ARRIVED,
    PICKED_UP,
    IN_PROGRESS,
    COMPLETED,
    CANCELLED;

    public Set<TripStatus> allowedNext() {
        return switch (this) {
            case SCHEDULED -> Set.of(DRIVER_EN_ROUTE, CANCELLED);
            case DRIVER_EN_ROUTE -> Set.of(DRIVER_ARRIVED, CANCELLED);
            case DRIVER_ARRIVED -> Set.of(PICKED_UP);
            case PICKED_UP -> Set.of(IN_PROGRESS);
            case IN_PROGRESS -> Set.of(COMPLETED);
            case COMPLETED, CANCELLED -> Set.of();
        };
    }

    public boolean canMoveTo(TripStatus next) {
        return next != null && allowedNext().contains(next);
    }

    /** True once the trip can no longer change status. */
    public boolean isFinal() {
        return allowedNext().isEmpty();
    }

    /** Reservations may only be created while the trip is still scheduled. */
    public boolean acceptsReservations() {
        return this == SCHEDULED;
    }

    /** The driver sends GPS positions from DRIVER_EN_ROUTE until the trip is completed. */
    public boolean acceptsPositions() {
        return this == DRIVER_EN_ROUTE || this == DRIVER_ARRIVED || this == PICKED_UP
                || this == IN_PROGRESS;
    }

    /**
     * Which end of the route the driver is heading for. The live view reports the distance and
     * ETA to this point.
     */
    public TrackingTarget trackingTarget() {
        return switch (this) {
            // Still on the way to the passenger. A cancelled trip never got anyone aboard.
            case SCHEDULED, DRIVER_EN_ROUTE, DRIVER_ARRIVED, CANCELLED -> TrackingTarget.PICKUP;
            case PICKED_UP, IN_PROGRESS, COMPLETED -> TrackingTarget.DROPOFF;
        };
    }
}
