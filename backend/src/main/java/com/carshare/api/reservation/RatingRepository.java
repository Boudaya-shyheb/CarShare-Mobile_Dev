package com.carshare.api.reservation;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RatingRepository extends JpaRepository<Rating, UUID> {

    Optional<Rating> findByTrip_IdAndFrom_IdAndTo_Id(UUID tripId, UUID fromId, UUID toId);

    /** Everything the caller left on one trip, for the completion screen. */
    List<Rating> findByTrip_IdAndFrom_Id(UUID tripId, UUID fromId);

    boolean existsByTrip_IdAndFrom_IdAndTo_Id(UUID tripId, UUID fromId, UUID toId);

    /**
     * The newest stars a user received, newest first. The average is taken over the page the
     * service asks for rather than over all history, so one bad month eventually drops off.
     */
    @Query("select r.stars from Rating r where r.to.id = :userId order by r.createdAt desc")
    List<Short> recentStars(@Param("userId") UUID userId, Pageable pageable);

    long countByTo_Id(UUID userId);

    /**
     * Average of the newest 50 ratings each listed user received, plus how many they have in
     * all. Native because it needs a window function: a plain GROUP BY cannot take "the last
     * fifty per user", and doing it per user would be one query per search result.
     */
    @Query(value = """
            SELECT ranked.to_user_id AS userId,
                   AVG(ranked.stars) FILTER (WHERE ranked.rn <= 50) AS average,
                   COUNT(*) AS total
            FROM (
                SELECT r.to_user_id, r.stars,
                       ROW_NUMBER() OVER (PARTITION BY r.to_user_id
                                          ORDER BY r.created_at DESC) AS rn
                FROM ratings r
                WHERE r.to_user_id IN (:userIds)
            ) ranked
            GROUP BY ranked.to_user_id
            """, nativeQuery = true)
    List<RatingSummaryRow> summariesFor(@Param("userIds") Collection<UUID> userIds);

    /** Projection for {@link #summariesFor}. */
    interface RatingSummaryRow {
        UUID getUserId();

        /** Mean of the newest fifty; null only if the user somehow has rows but none ranked. */
        Double getAverage();

        /** Every rating they ever received, not just the fifty the average used. */
        long getTotal();
    }
}
