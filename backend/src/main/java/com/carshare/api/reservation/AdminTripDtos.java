package com.carshare.api.reservation;

import java.util.List;

/**
 * What the admin trip detail and the dashboard counters receive. The trips list itself belongs to
 * the admin operations screens ({@code GET /api/admin/trips}); this holds the Reservation module's
 * own admin records.
 */
public final class AdminTripDtos {
    private AdminTripDtos() { }

    /** One trip with everyone who booked it and everything that happened to it. */
    public record AdminTripDetail(TripDtos.TripDetail trip,
            List<ReservationDtos.PassengerView> reservations, List<TripDtos.EventView> events) { }

    /** The trip and reservation figures on the admin dashboard. */
    public record TripCounts(long total, long inProgress, long completed, long cancelled,
            long reservations) { }
}
