package com.carshare.api.reservation;

import java.util.UUID;

/**
 * Scores how well a published trip matches what a passenger asked for, out of 100.
 *
 * <pre>
 * pickup distance      35 pts  full at 0 m,   0 at 2000 m
 * drop-off distance    25 pts  full at 0 m,   0 at 2000 m
 * time gap             25 pts  full at 0 min, 0 at 60 min
 * driver reliability   15 pts  flat for now
 * </pre>
 *
 * Every component falls off linearly. Pure and static so it can be unit tested on its own.
 */
public final class MatchScorer {
    public static final int MAX_PICKUP_POINTS = 35;
    public static final int MAX_DROPOFF_POINTS = 25;
    public static final int MAX_TIME_POINTS = 25;
    public static final int MAX_RELIABILITY_POINTS = 15;

    /** A trip further than this from either end of the requested route is not a match at all. */
    public static final double MAX_DISTANCE_M = 2_000d;
    public static final long MAX_TIME_GAP_MINUTES = 60L;

    /** Results below this score are not returned. */
    public static final int MINIMUM_SCORE = 50;

    private MatchScorer() { }

    public static int score(double pickupDistanceM, double dropoffDistanceM, long timeGapMinutes,
            UUID driverId) {
        double points = linearPoints(pickupDistanceM, MAX_DISTANCE_M, MAX_PICKUP_POINTS)
                + linearPoints(dropoffDistanceM, MAX_DISTANCE_M, MAX_DROPOFF_POINTS)
                + linearPoints(timeGapMinutes, MAX_TIME_GAP_MINUTES, MAX_TIME_POINTS)
                + driverReliabilityPoints(driverId);
        return (int) Math.round(Math.max(0d, Math.min(100d, points)));
    }

    /**
     * TODO(ratings step): replace the flat score with the driver's average rating and punctuality
     * (share of trips started on time). Until the ratings table exists every driver scores the
     * full 15 points, so this component does not change the ordering.
     */
    public static int driverReliabilityPoints(UUID driverId) {
        return MAX_RELIABILITY_POINTS;
    }

    public static boolean isMatch(int score) {
        return score >= MINIMUM_SCORE;
    }

    private static double linearPoints(double value, double limit, int maxPoints) {
        if (value <= 0d) return maxPoints;
        if (value >= limit) return 0d;
        return maxPoints * (1d - value / limit);
    }
}
