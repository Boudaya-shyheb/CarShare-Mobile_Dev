package com.carshare.api.admin;

/** What the admin dashboard endpoint returns. */
public final class AdminDtos {
    private AdminDtos() { }

    /**
     * The counters at the top of the dashboard. Trips "in progress" are the ones the driver has
     * set off on and not yet finished.
     */
    public record Stats(long users, long tripsTotal, long tripsInProgress, long tripsCompleted,
            long tripsCancelled, long reservations, long lostAndFoundReports) { }
}
