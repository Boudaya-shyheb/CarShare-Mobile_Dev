package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class MatchScorerTest {
    private static final UUID DRIVER = UUID.randomUUID();

    @Test
    @DisplayName("an exact match scores 100")
    void exactMatchScoresFull() {
        assertEquals(100, MatchScorer.score(0, 0, 0, DRIVER));
    }

    @Test
    @DisplayName("at both distance limits and the time limit only reliability is left")
    void allComponentsAtTheirLimitLeaveReliabilityOnly() {
        assertEquals(MatchScorer.MAX_RELIABILITY_POINTS, MatchScorer.score(2_000, 2_000, 60, DRIVER));
    }

    @Test
    @DisplayName("beyond the limits the components stay at zero instead of going negative")
    void componentsAreClampedBeyondTheirLimit() {
        assertEquals(MatchScorer.MAX_RELIABILITY_POINTS,
                MatchScorer.score(50_000, 80_000, 600, DRIVER));
    }

    @Test
    @DisplayName("halfway to the pickup limit costs half of the 35 points")
    void halfwayPickupDistanceCostsHalfThePoints() {
        // 17.5 + 25 + 25 + 15 = 82.5, rounded half up
        assertEquals(83, MatchScorer.score(1_000, 0, 0, DRIVER));
    }

    @Test
    @DisplayName("halfway to the drop-off limit costs half of the 25 points")
    void halfwayDropoffDistanceCostsHalfThePoints() {
        // 35 + 12.5 + 25 + 15 = 87.5
        assertEquals(88, MatchScorer.score(0, 1_000, 0, DRIVER));
    }

    @Test
    @DisplayName("half of the time window costs half of the 25 points")
    void halfTheTimeWindowCostsHalfThePoints() {
        // 35 + 25 + 12.5 + 15 = 87.5
        assertEquals(88, MatchScorer.score(0, 0, 30, DRIVER));
    }

    @Test
    @DisplayName("a quarter of the way costs a quarter of each component")
    void quarterDistancesAreLinear() {
        // 26.25 + 18.75 + 18.75 + 15 = 78.75
        assertEquals(79, MatchScorer.score(500, 500, 15, DRIVER));
    }

    @Test
    @DisplayName("the time gap is measured in whole minutes, in either direction")
    void timeGapIsAbsolute() {
        assertEquals(MatchScorer.score(0, 0, 20, DRIVER), MatchScorer.score(0, 0, 20, DRIVER));
        assertTrue(MatchScorer.score(0, 0, 10, DRIVER) > MatchScorer.score(0, 0, 40, DRIVER));
    }

    @Test
    @DisplayName("every driver scores the full reliability points for now")
    void reliabilityIsFlat() {
        assertEquals(15, MatchScorer.MAX_RELIABILITY_POINTS);
        assertEquals(15, MatchScorer.driverReliabilityPoints(DRIVER));
        assertEquals(15, MatchScorer.driverReliabilityPoints(UUID.randomUUID()));
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
        assertEquals(50, MatchScorer.score(0, 2_000, 60, DRIVER));
        assertTrue(MatchScorer.isMatch(MatchScorer.score(0, 2_000, 60, DRIVER)));
    }

    @Test
    @DisplayName("a slightly worse pickup drops below the threshold")
    void justBelowTheThresholdIsNotAMatch() {
        // 33.25 + 0 + 0 + 15 = 48.25
        assertEquals(48, MatchScorer.score(100, 2_000, 60, DRIVER));
        assertFalse(MatchScorer.isMatch(MatchScorer.score(100, 2_000, 60, DRIVER)));
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
                    int score = MatchScorer.score(pickup, dropoff, gap, DRIVER);
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
            int score = MatchScorer.score(pickup, 0, 0, DRIVER);
            assertTrue(score <= previous, "score rose at pickup=" + pickup);
            previous = score;
        }
    }
}
