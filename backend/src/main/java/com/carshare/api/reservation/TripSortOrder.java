package com.carshare.api.reservation;

import com.carshare.api.common.ApiException;
import java.util.Comparator;
import java.util.Locale;
import org.springframework.http.HttpStatus;

/** The orderings the search endpoint accepts in its {@code sort} parameter. */
public enum TripSortOrder {
    /** Closest match first, then the one leaving soonest. */
    BEST("best"),
    /** Cheapest seat first, then the better match. */
    CHEAPEST("cheapest"),
    /** Leaving soonest first. */
    EARLIEST("earliest");

    private final String parameter;

    TripSortOrder(String parameter) {
        this.parameter = parameter;
    }

    public String parameter() {
        return parameter;
    }

    public static TripSortOrder fromParameter(String value) {
        if (value == null || value.isBlank()) {
            return BEST;
        }
        String wanted = value.trim().toLowerCase(Locale.ROOT);
        for (TripSortOrder order : values()) {
            if (order.parameter.equals(wanted)) {
                return order;
            }
        }
        throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_search",
                "Sort by best, cheapest, or earliest.");
    }

    public Comparator<TripDtos.TripSearchResult> comparator() {
        return switch (this) {
            case BEST -> Comparator.comparingInt(TripDtos.TripSearchResult::matchScore).reversed()
                    .thenComparing(TripDtos.TripSearchResult::departureTime, Comparator.naturalOrder());
            case CHEAPEST -> Comparator.comparing(TripDtos.TripSearchResult::pricePerSeat)
                    .thenComparing(Comparator.comparingInt(TripDtos.TripSearchResult::matchScore).reversed());
            case EARLIEST -> Comparator.comparing(TripDtos.TripSearchResult::departureTime);
        };
    }
}
