package com.carshare.api.reservation;

import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * What a user's history says about them: the stars other people left, and how often they turned
 * up on time.
 *
 * <p>Everything here is batched. A search returns up to 50 trips, and asking two questions per
 * driver one at a time would be a hundred round trips to Neon for one screen.
 */
@Service
public class ReputationService {

    /** The average is taken over this many of the newest ratings, so old history fades out. */
    public static final int RATING_WINDOW = 50;

    private final RatingRepository ratings;
    private final TripEventRepository tripEvents;

    public ReputationService(RatingRepository ratings, TripEventRepository tripEvents) {
        this.ratings = ratings;
        this.tripEvents = tripEvents;
    }

    /**
     * One person's reputation.
     *
     * @param average     mean of the last {@link #RATING_WINDOW} ratings, null when never rated
     * @param count       how many ratings they have received in total
     * @param punctuality share of completed trips they arrived on time for, null with no data
     */
    public record Reputation(Double average, long count, Double punctuality) {
        public static final Reputation NONE = new Reputation(null, 0L, null);
    }

    @Transactional(readOnly = true)
    public Reputation forUser(UUID userId) {
        return forUsers(Set.of(userId)).getOrDefault(userId, Reputation.NONE);
    }

    /** Ratings only — for a passenger, where punctuality has no meaning. */
    @Transactional(readOnly = true)
    public Map<UUID, Reputation> ratingsFor(Collection<UUID> userIds) {
        Map<UUID, Reputation> out = new HashMap<>();
        if (userIds.isEmpty()) return out;
        for (RatingRepository.RatingSummaryRow row : ratings.summariesFor(Set.copyOf(userIds))) {
            out.put(row.getUserId(), new Reputation(round(row.getAverage()), row.getTotal(), null));
        }
        return out;
    }

    /** Ratings and punctuality, for drivers. */
    @Transactional(readOnly = true)
    public Map<UUID, Reputation> forUsers(Collection<UUID> userIds) {
        Map<UUID, Reputation> out = new HashMap<>(ratingsFor(userIds));
        if (userIds.isEmpty()) return out;
        for (TripEventRepository.PunctualityRow row
                : tripEvents.punctualityFor(Set.copyOf(userIds))) {
            Reputation current = out.getOrDefault(row.getDriverId(), Reputation.NONE);
            Double punctuality = row.getTotal() == 0
                    ? null
                    : (double) row.getOnTime() / row.getTotal();
            out.put(row.getDriverId(),
                    new Reputation(current.average(), current.count(), punctuality));
        }
        return out;
    }

    /** Rounds to one decimal, which is all the UI shows ("4.8"). */
    private static Double round(Double value) {
        return value == null ? null : Math.round(value * 10d) / 10d;
    }

    /** Convenience for the places that already hold a list of ids and want a total. */
    @Transactional(readOnly = true)
    public List<Short> recentStars(UUID userId) {
        return ratings.recentStars(userId,
                org.springframework.data.domain.PageRequest.of(0, RATING_WINDOW));
    }
}
