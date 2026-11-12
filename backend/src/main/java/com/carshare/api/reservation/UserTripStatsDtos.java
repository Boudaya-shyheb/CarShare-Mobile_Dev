package com.carshare.api.reservation;

/** Response shapes of {@code GET /api/users/me/stats}. */
public final class UserTripStatsDtos {
    private UserTripStatsDtos() { }

    /**
     * What the Profile screen's Trips / Rating / No-shows card shows.
     *
     * @param tripsAsDriver    trips this user drove to COMPLETED
     * @param tripsAsPassenger reservations of theirs that ended COMPLETED
     * @param totalTrips       the two added together
     * @param rating           mean of the newest 50 ratings, one decimal; null when never rated
     * @param ratingCount      every rating received, not only the 50 the mean used
     * @param noShows          times a driver marked them a no-show as a passenger
     * @param reliability      the driver-reliability points the match score gives them, 0 to 15
     */
    public record UserTripStats(long tripsAsDriver, long tripsAsPassenger, long totalTrips,
            Double rating, long ratingCount, long noShows, int reliability) { }
}
