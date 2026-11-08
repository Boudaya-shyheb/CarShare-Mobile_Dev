package com.carshare.api.reservation;

/** Audit trail entries written to {@code trip_events}. */
public enum TripEventType {
    PUBLISHED,
    UPDATED,
    DRIVER_EN_ROUTE,
    DRIVER_ARRIVED,
    PICKED_UP,
    IN_PROGRESS,
    COMPLETED,
    CANCELLED,
    CHECK_IN,
    NO_SHOW,
    DEVIATION,
    RESERVATION_REQUESTED,
    RESERVATION_CONFIRMED,
    RESERVATION_REFUSED,
    RESERVATION_CANCELLED;

    public static TripEventType forStatus(TripStatus status) {
        return switch (status) {
            case SCHEDULED -> PUBLISHED;
            case DRIVER_EN_ROUTE -> DRIVER_EN_ROUTE;
            case DRIVER_ARRIVED -> DRIVER_ARRIVED;
            case PICKED_UP -> PICKED_UP;
            case IN_PROGRESS -> IN_PROGRESS;
            case COMPLETED -> COMPLETED;
            case CANCELLED -> CANCELLED;
        };
    }
}
