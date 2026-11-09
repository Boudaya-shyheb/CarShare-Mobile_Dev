package com.carshare.api.reservation;

/**
 * Lifecycle of a seat request.
 *
 * <pre>
 * PENDING    → CONFIRMED (driver accepts, or instant booking) | REFUSED (driver, or auto-refuse)
 *            → CANCELLED (passenger, or the driver cancels the trip)
 * CONFIRMED  → CANCELLED (passenger, or the driver cancels the trip)
 *            → NO_SHOW | COMPLETED (live tracking, step 6)
 * </pre>
 */
public enum ReservationStatus {
    PENDING,
    CONFIRMED,
    REFUSED,
    CANCELLED,
    NO_SHOW,
    COMPLETED;

    /** Active reservations hold a seat on the trip and block an overlapping booking. */
    public boolean isActive() {
        return this == PENDING || this == CONFIRMED;
    }

    /** Only a PENDING reservation can be accepted or refused. */
    public boolean awaitsDecision() {
        return this == PENDING;
    }

    /** CONFIRMED reservations are the ones counted in {@code trips.confirmed_seats}. */
    public boolean holdsConfirmedSeat() {
        return this == CONFIRMED;
    }
}
