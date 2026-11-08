package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** The [departure, expected arrival) window the overlap rule is built on. */
class TripWindowTest {
    private static final Instant NOON = Instant.parse("2026-11-20T12:00:00Z");

    private final AppUser driver =
            new AppUser("Driver", "+21611111111", "driver@carshare.tn", "hash", UserRole.DRIVER);

    @Test
    @DisplayName("a trip without a route duration is assumed to take two hours")
    void defaultsToTwoHours() {
        Trip trip = tripAt(NOON, null);

        assertEquals(Duration.ofHours(2), trip.expectedDuration());
        assertEquals(NOON.plus(2, ChronoUnit.HOURS), trip.expectedArrival());
        assertEquals(Duration.ofHours(2), Trip.DEFAULT_DURATION);
    }

    @Test
    @DisplayName("a trip with a route duration uses it")
    void usesRouteDuration() {
        Trip trip = tripAt(NOON, 5_400); // 90 minutes

        assertEquals(Duration.ofMinutes(90), trip.expectedDuration());
        assertEquals(NOON.plus(90, ChronoUnit.MINUTES), trip.expectedArrival());
    }

    @Test
    @DisplayName("a trip overlaps itself")
    void overlapsItself() {
        Trip trip = tripAt(NOON, null);

        assertTrue(trip.overlaps(trip));
    }

    @Test
    @DisplayName("two trips at the same time overlap")
    void sameTimeOverlaps() {
        assertTrue(tripAt(NOON, null).overlaps(tripAt(NOON, null)));
    }

    @Test
    @DisplayName("a trip starting one minute before the other arrives overlaps")
    void overlapsByOneMinute() {
        Trip first = tripAt(NOON, null); // arrives 14:00
        Trip second = tripAt(NOON.plus(119, ChronoUnit.MINUTES), null); // leaves 13:59

        assertTrue(first.overlaps(second));
        assertTrue(second.overlaps(first));
    }

    @Test
    @DisplayName("back-to-back trips do not overlap")
    void backToBackDoesNotOverlap() {
        Trip first = tripAt(NOON, null); // arrives exactly 14:00
        Trip second = tripAt(NOON.plus(2, ChronoUnit.HOURS), null); // leaves exactly 14:00

        assertFalse(first.overlaps(second));
        assertFalse(second.overlaps(first));
    }

    @Test
    @DisplayName("a short known duration frees the diary earlier than the two-hour default")
    void shortDurationFreesTheDiary() {
        Trip quick = tripAt(NOON, 1_800); // 30 minutes, arrives 12:30
        Trip later = tripAt(NOON.plus(45, ChronoUnit.MINUTES), null);

        assertFalse(quick.overlaps(later));
        // The same pair would overlap if the first trip had no known duration.
        assertTrue(tripAt(NOON, null).overlaps(later));
    }

    @Test
    @DisplayName("trips far apart do not overlap")
    void farApartDoesNotOverlap() {
        assertFalse(tripAt(NOON, null).overlaps(tripAt(NOON.plus(2, ChronoUnit.DAYS), null)));
    }

    @Test
    @DisplayName("the overlap test is symmetric across a range of offsets")
    void overlapIsSymmetric() {
        Trip first = tripAt(NOON, null);
        for (int minutes = -240; minutes <= 240; minutes += 15) {
            Trip second = tripAt(NOON.plus(minutes, ChronoUnit.MINUTES), null);
            assertEquals(first.overlaps(second), second.overlaps(first),
                    "asymmetric at " + minutes + " minutes");
        }
    }

    private Trip tripAt(Instant departure, Integer durationS) {
        return new Trip(driver, null, "Origin", 36.8, 10.18, "Destination", 35.82, 10.63,
                departure, 4, new BigDecimal("12.00"), false, null, null, durationS);
    }
}
