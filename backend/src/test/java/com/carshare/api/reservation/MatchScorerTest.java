package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class MatchScorerTest {
    /** A driver with the best possible history: the reliability component is then its full 15. */
    private static final Double FIVE_STARS = 5.0d;
    private static final Double ALWAYS_ON_TIME = 1.0d;

    @Test
    @DisplayName("an exact match scores 100")
    void exactMatchScoresFull() {
        assertEquals(100, MatchScorer.score(0, 0, 0, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("at both distance limits and the time limit only reliability is left")
    void allComponentsAtTheirLimitLeaveReliabilityOnly() {
        assertEquals(MatchScorer.MAX_RELIABILITY_POINTS, MatchScorer.score(2_000, 2_000, 60, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("beyond the limits the components stay at zero instead of going negative")
    void componentsAreClampedBeyondTheirLimit() {
        assertEquals(MatchScorer.MAX_RELIABILITY_POINTS,
                MatchScorer.score(50_000, 80_000, 600, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("halfway to the pickup limit costs half of the 35 points")
    void halfwayPickupDistanceCostsHalfThePoints() {
        // 17.5 + 25 + 25 + 15 = 82.5, rounded half up
        assertEquals(83, MatchScorer.score(1_000, 0, 0, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("halfway to the drop-off limit costs half of the 25 points")
    void halfwayDropoffDistanceCostsHalfThePoints() {
        // 35 + 12.5 + 25 + 15 = 87.5
        assertEquals(88, MatchScorer.score(0, 1_000, 0, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("half of the time window costs half of the 25 points")
    void halfTheTimeWindowCostsHalfThePoints() {
        // 35 + 25 + 12.5 + 15 = 87.5
        assertEquals(88, MatchScorer.score(0, 0, 30, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("a quarter of the way costs a quarter of each component")
    void quarterDistancesAreLinear() {
        // 26.25 + 18.75 + 18.75 + 15 = 78.75
        assertEquals(79, MatchScorer.score(500, 500, 15, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("the time gap is measured in whole minutes, in either direction")
    void timeGapIsAbsolute() {
        assertEquals(MatchScorer.score(0, 0, 20, FIVE_STARS, ALWAYS_ON_TIME), MatchScorer.score(0, 0, 20, FIVE_STARS, ALWAYS_ON_TIME));
        assertTrue(MatchScorer.score(0, 0, 10, FIVE_STARS, ALWAYS_ON_TIME) > MatchScorer.score(0, 0, 40, FIVE_STARS, ALWAYS_ON_TIME));
    }

    @Test
    @DisplayName("reliability is 60% what people said and 40% whether the driver turns up")
    void reliabilitySplitsRatingAndPunctuality() {
        assertEquals(15, MatchScorer.MAX_RELIABILITY_POINTS);
        assertEquals(15, MatchScorer.driverReliabilityPoints(FIVE_STARS, ALWAYS_ON_TIME));
        assertEquals(0, MatchScorer.driverReliabilityPoints(0.0d, 0.0d));
        // 15 x (0.6 x 4/5 + 0.4 x 0.5) = 15 x 0.68 = 10.2
        assertEquals(10, MatchScorer.driverReliabilityPoints(4.0d, 0.5d));
    }

    @Test
    @DisplayName("a driver with no history at all is neither buried nor promoted")
    void newDriverGetsTheMiddleGround() {
        assertEquals(MatchScorer.NEW_DRIVER_RELIABILITY_POINTS,
                MatchScorer.driverReliabilityPoints(null, null));
        assertTrue(MatchScorer.NEW_DRIVER_RELIABILITY_POINTS
                < MatchScorer.driverReliabilityPoints(FIVE_STARS, ALWAYS_ON_TIME));
        assertTrue(MatchScorer.NEW_DRIVER_RELIABILITY_POINTS
                > MatchScorer.driverReliabilityPoints(1.0d, 0.0d));
    }

    @Test
    @DisplayName("when only one half is known it stands for the whole component")
    void onePartMissingIsNotPenalised() {
        // Rated five stars but never completed a trip: the rating carries the full 15.
        assertEquals(15, MatchScorer.driverReliabilityPoints(FIVE_STARS, null));
        // Always on time but never rated: punctuality carries it.
        assertEquals(15, MatchScorer.driverReliabilityPoints(null, ALWAYS_ON_TIME));
        assertEquals(9, MatchScorer.driverReliabilityPoints(3.0d, null));
    }

    @Test
    @DisplayName("the components add up to 100")
    void componentsAddUpToOneHundred() {
        assertEquals(100, MatchScorer.MAX_PICKUP_POINTS + MatchScorer.MAX_DROPOFF_POINTS
                + MatchScorer.MAX_TIME_POINTS + MatchScorer.MAX_RELIABILITY_POINTS);
    }

    @Test
    @DisplayName("a perfect pickup with nothing else still just reaches the threshold")
    void perfectPickupAloneIsTheThresholdCase() {
        // 35 + 0 + 0 + 15 = 50
        assertEquals(50, MatchScorer.score(0, 2_000, 60, FIVE_STARS, ALWAYS_ON_TIME));
        assertTrue(MatchScorer.isMatch(MatchScorer.score(0, 2_000, 60, FIVE_STARS, ALWAYS_ON_TIME)));
    }

    @Test
    @DisplayName("a slightly worse pickup drops below the threshold")
    void justBelowTheThresholdIsNotAMatch() {
        // 33.25 + 0 + 0 + 15 = 48.25
        assertEquals(48, MatchScorer.score(100, 2_000, 60, FIVE_STARS, ALWAYS_ON_TIME));
        assertFalse(MatchScorer.isMatch(MatchScorer.score(100, 2_000, 60, FIVE_STARS, ALWAYS_ON_TIME)));
    }

    @Test
    @DisplayName("the threshold itself counts as a match")
    void thresholdIsInclusive() {
        assertEquals(50, MatchScorer.MINIMUM_SCORE);
        assertTrue(MatchScorer.isMatch(50));
        assertFalse(MatchScorer.isMatch(49));
    }

    @Test
    @DisplayName("the score never leaves the 0 to 100 range")
    void scoreStaysInRange() {
        for (int pickup = 0; pickup <= 4_000; pickup += 250) {
            for (int dropoff = 0; dropoff <= 4_000; dropoff += 250) {
                for (int gap = 0; gap <= 120; gap += 10) {
                    int score = MatchScorer.score(pickup, dropoff, gap, FIVE_STARS, ALWAYS_ON_TIME);
                    assertTrue(score >= 0 && score <= 100,
                            "pickup=" + pickup + " dropoff=" + dropoff + " gap=" + gap + " -> " + score);
                }
            }
        }
    }

    @Test
    @DisplayName("a closer trip always scores at least as high as a further one")
    void scoreDecreasesWithDistance() {
        int previous = Integer.MAX_VALUE;
        for (int pickup = 0; pickup <= 2_000; pickup += 100) {
            int score = MatchScorer.score(pickup, 0, 0, FIVE_STARS, ALWAYS_ON_TIME);
            assertTrue(score <= previous, "score rose at pickup=" + pickup);
            previous = score;
        }
    }
}
