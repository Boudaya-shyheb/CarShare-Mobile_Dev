package com.carshare.api.reservation;

/**
 * Scores how well a published trip matches what a passenger asked for, out of 100.
 *
 * <pre>
 * pickup distance      35 pts  full at 0 m,   0 at 2000 m
 * drop-off distance    25 pts  full at 0 m,   0 at 2000 m
 * time gap             25 pts  full at 0 min, 0 at 60 min
 * driver reliability   15 pts  60% rating, 40% punctuality
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

    /** Points a driver with no history at all gets, so a newcomer is not buried. */
    public static final int NEW_DRIVER_RELIABILITY_POINTS = 10;

    /** How the reliability points split between what people said and whether they turn up. */
    public static final double RATING_WEIGHT = 0.6d;
    public static final double PUNCTUALITY_WEIGHT = 0.4d;

    public static int score(double pickupDistanceM, double dropoffDistanceM, long timeGapMinutes,
            Double driverRating, Double driverPunctuality) {
        double points = linearPoints(pickupDistanceM, MAX_DISTANCE_M, MAX_PICKUP_POINTS)
                + linearPoints(dropoffDistanceM, MAX_DISTANCE_M, MAX_DROPOFF_POINTS)
                + linearPoints(timeGapMinutes, MAX_TIME_GAP_MINUTES, MAX_TIME_POINTS)
                + driverReliabilityPoints(driverRating, driverPunctuality);
        return (int) Math.round(Math.max(0d, Math.min(100d, points)));
    }

    /**
     * 15 x (0.6 x rating/5 + 0.4 x punctuality).
     *
     * <p>A driver with neither a rating nor a completed trip scores
     * {@link #NEW_DRIVER_RELIABILITY_POINTS} rather than 0 or 15: a newcomer should not be
     * buried under established drivers, nor beat them before doing anything. When only one of
     * the two is known, that half is scaled up to stand for the whole component, so a missing
     * figure neither helps nor hurts.
     */
    public static int driverReliabilityPoints(Double rating, Double punctuality) {
        boolean hasRating = rating != null;
        boolean hasPunctuality = punctuality != null;
        if (!hasRating && !hasPunctuality) return NEW_DRIVER_RELIABILITY_POINTS;

        double share;
        if (hasRating && hasPunctuality) {
            share = RATING_WEIGHT * clamp01(rating / Rating.MAX_STARS)
                    + PUNCTUALITY_WEIGHT * clamp01(punctuality);
        } else if (hasRating) {
            share = clamp01(rating / Rating.MAX_STARS);
        } else {
            share = clamp01(punctuality);
        }
        return (int) Math.round(MAX_RELIABILITY_POINTS * share);
    }

    private static double clamp01(double value) {
        return Math.max(0d, Math.min(1d, value));
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
