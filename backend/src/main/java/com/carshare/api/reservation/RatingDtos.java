package com.carshare.api.reservation;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.UUID;

public final class RatingDtos {
    private RatingDtos() { }

    public record RateRequest(@NotNull UUID toUserId,
            @Min(Rating.MIN_STARS) @Max(Rating.MAX_STARS) int stars,
            @Size(max = 500) String comment) { }

    /** A PUT revises a rating already left, so it does not repeat who it is about. */
    public record ReviseRatingRequest(@Min(Rating.MIN_STARS) @Max(Rating.MAX_STARS) int stars,
            @Size(max = 500) String comment) { }

    public record RatingView(UUID id, UUID tripId, UUID fromUserId, UUID toUserId,
            String toUserName, int stars, String comment, boolean editable,
            Instant createdAt, Instant updatedAt) {
        public static RatingView from(Rating rating, Instant now) {
            return new RatingView(rating.getId(), rating.getTrip().getId(),
                    rating.getFrom().getId(), rating.getTo().getId(),
                    rating.getTo().getFullName(), rating.getStars(), rating.getComment(),
                    rating.isEditableAt(now), rating.getCreatedAt(), rating.getUpdatedAt());
        }
    }

    /**
     * Who the caller may rate on a finished trip, and what they have already said.
     *
     * <p>The completion screen draws itself from this one call: a passenger gets a single row for
     * their driver, a driver gets one row per passenger who actually boarded.
     */
    public record RatableParty(UUID userId, String name, String role, RatingView myRating) { }

    public record MyRatings(UUID tripId, boolean tripCompleted, java.util.List<RatableParty> parties) { }
}
