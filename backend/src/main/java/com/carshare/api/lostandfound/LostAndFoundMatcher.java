package com.carshare.api.lostandfound;

import java.util.Locale;
import java.util.Optional;
import java.util.Set;

/**
 * Whether a lost report and a found report look like the same item. The phone applies the same
 * rule when it offers a match, so the server's "Match found" notification and the app's "Match
 * found" screen never disagree: same trip, opposite type, two different people, the same
 * category and, when both gave one, the same colour.
 */
final class LostAndFoundMatcher {
    /** The categories the report form offers, lower case. "Other" is left out on purpose: it matches nothing. */
    static final Set<String> CATEGORIES =
            Set.of("phone", "keys", "wallet", "bag", "documents", "glasses", "clothing");

    /** The report's description ends with this marker and the colour, as the app writes it. */
    static final String COLOR_MARKER = "\n\nColor: ";

    private LostAndFoundMatcher() { }

    /** The report's category, taken from its title; empty for "Other" or a free-text title. */
    static Optional<String> category(String title) {
        String normalized = title == null ? "" : title.trim().toLowerCase(Locale.ROOT);
        return CATEGORIES.contains(normalized) ? Optional.of(normalized) : Optional.empty();
    }

    static String color(String description) {
        if (description == null) return "";
        int start = description.lastIndexOf(COLOR_MARKER);
        return start < 0 ? "" : description.substring(start + COLOR_MARKER.length()).trim();
    }

    /** Same rule, optionally ignoring whether the reports are still open (photo access, history). */
    static boolean matches(LostAndFoundReport a, LostAndFoundReport b, boolean requireOpen) {
        if (a.getType() == b.getType()) return false;
        if (!a.getTrip().getId().equals(b.getTrip().getId())) return false;
        if (a.getReporter().getId().equals(b.getReporter().getId())) return false;
        if (requireOpen && (a.getStatus() != LostAndFoundReport.Status.OPEN
                || b.getStatus() != LostAndFoundReport.Status.OPEN)) {
            return false;
        }
        Optional<String> category = category(a.getTitle());
        if (category.isEmpty() || !category.equals(category(b.getTitle()))) return false;
        String colourA = color(a.getDescription());
        String colourB = color(b.getDescription());
        return colourA.isEmpty() || colourB.isEmpty() || colourA.equalsIgnoreCase(colourB);
    }

    /** Higher is better: an exact colour match beats a match where one side gave no colour. */
    static int score(LostAndFoundReport a, LostAndFoundReport b) {
        String colourA = color(a.getDescription());
        return !colourA.isEmpty() && colourA.equalsIgnoreCase(color(b.getDescription())) ? 2 : 1;
    }
}
