package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.carshare.api.reservation.Trip;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class LostAndFoundMatcherTest {
    private AppUser owner;
    private AppUser finder;
    private Trip trip;

    @BeforeEach
    void setUp() {
        owner = new AppUser("Ines", "+21698765432", "ines@carshare.tn", "h", UserRole.PASSENGER);
        finder = new AppUser("Yacine", "+21612345678", "yacine@carshare.tn", "h", UserRole.DRIVER);
        trip = new Trip(finder, null, "Ennasr", 36.8, 10.15, "Sousse", 35.8, 10.6,
                Instant.now().plusSeconds(7200), 3, new BigDecimal("10.00"), false, null, null, null, null);
    }

    private LostAndFoundReport report(Trip on, AppUser by, LostAndFoundReport.Type type, String title, String colour) {
        return new LostAndFoundReport(on, by, type, title,
                "A thing" + (colour == null ? "" : "\n\nColor: " + colour));
    }

    @Test
    @DisplayName("a lost and a found report of the same category on the same trip match")
    void sameCategoryMatches() {
        var lost = report(trip, owner, LostAndFoundReport.Type.LOST, "Phone", "Black");
        var found = report(trip, finder, LostAndFoundReport.Type.FOUND, "phone", "black");

        assertTrue(LostAndFoundMatcher.matches(lost, found, true));
        assertTrue(LostAndFoundMatcher.matches(found, lost, true));
    }

    @Test
    @DisplayName("every form category matches itself, glasses and clothing included")
    void newCategoriesMatch() {
        for (String category : new String[] {"Phone", "Keys", "Wallet", "Bag", "Documents", "Glasses", "Clothing"}) {
            assertTrue(LostAndFoundMatcher.matches(
                    report(trip, owner, LostAndFoundReport.Type.LOST, category, null),
                    report(trip, finder, LostAndFoundReport.Type.FOUND, category, null), true), category);
        }
    }

    @Test
    @DisplayName("Other, a free-text title or a different category never match")
    void otherAndDifferentCategoriesDoNotMatch() {
        assertFalse(LostAndFoundMatcher.matches(
                report(trip, owner, LostAndFoundReport.Type.LOST, "Other", null),
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Other", null), true));
        assertFalse(LostAndFoundMatcher.matches(
                report(trip, owner, LostAndFoundReport.Type.LOST, "Black thing", null),
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Black thing", null), true));
        assertFalse(LostAndFoundMatcher.matches(
                report(trip, owner, LostAndFoundReport.Type.LOST, "Phone", null),
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Keys", null), true));
    }

    @Test
    @DisplayName("two different colours do not match, but a missing colour on either side does")
    void colourRule() {
        var lost = report(trip, owner, LostAndFoundReport.Type.LOST, "Bag", "Red");

        assertFalse(LostAndFoundMatcher.matches(lost,
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Bag", "Blue"), true));
        assertTrue(LostAndFoundMatcher.matches(lost,
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Bag", null), true));
        assertTrue(LostAndFoundMatcher.matches(
                report(trip, owner, LostAndFoundReport.Type.LOST, "Bag", null),
                report(trip, finder, LostAndFoundReport.Type.FOUND, "Bag", "Blue"), true));
    }

    @Test
    @DisplayName("same type, same person or another trip never match")
    void structuralRules() {
        var lost = report(trip, owner, LostAndFoundReport.Type.LOST, "Phone", null);
        Trip other = new Trip(finder, null, "Tunis", 36.8, 10.18, "Sfax", 34.7, 10.7,
                Instant.now().plusSeconds(9000), 3, new BigDecimal("10.00"), false, null, null, null, null);

        assertFalse(LostAndFoundMatcher.matches(lost,
                report(trip, finder, LostAndFoundReport.Type.LOST, "Phone", null), true));
        assertFalse(LostAndFoundMatcher.matches(lost,
                report(trip, owner, LostAndFoundReport.Type.FOUND, "Phone", null), true));
        assertFalse(LostAndFoundMatcher.matches(lost,
                report(other, finder, LostAndFoundReport.Type.FOUND, "Phone", null), true));
    }

    @Test
    @DisplayName("a resolved report matches only when open-ness is ignored")
    void openNessIsOptional() {
        var lost = report(trip, owner, LostAndFoundReport.Type.LOST, "Phone", null);
        var found = report(trip, finder, LostAndFoundReport.Type.FOUND, "Phone", null);
        found.resolve();

        assertFalse(LostAndFoundMatcher.matches(lost, found, true));
        assertTrue(LostAndFoundMatcher.matches(lost, found, false));
    }

    @Test
    @DisplayName("category and colour are read from the title and the description's last line")
    void parsing() {
        assertEquals(Optional.of("phone"), LostAndFoundMatcher.category("  Phone "));
        assertEquals(Optional.empty(), LostAndFoundMatcher.category("Other"));
        assertEquals("Black", LostAndFoundMatcher.color("Cracked\n\nColor: Black"));
        assertEquals("", LostAndFoundMatcher.color("No colour here"));
    }
}
