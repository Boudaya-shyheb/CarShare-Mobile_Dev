package com.carshare.api.reservation;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TripEventRepository extends JpaRepository<TripEvent, UUID> {
    List<TripEvent> findByTrip_IdOrderByCreatedAtAsc(UUID tripId);

    /** The no-show rule measures the wait from the latest DRIVER_ARRIVED event. */
    Optional<TripEvent> findFirstByTrip_IdAndTypeOrderByCreatedAtDesc(UUID tripId,
            TripEventType type);

    /**
     * Punctuality per driver: of their completed trips, how many they reached the pickup point
     * within five minutes of the time they advertised.
     *
     * <p>Native because it compares a timestamp against another column plus an interval, which
     * JPQL cannot express, and because one query for every driver on a results page is cheaper
     * than one per driver.
     */
    @Query(value = """
            SELECT t.driver_id AS driverId,
                   COUNT(*) FILTER (
                       WHERE e.created_at <= t.departure_time + INTERVAL '5 minutes'
                   ) AS onTime,
                   COUNT(*) AS total
            FROM trip_events e
            JOIN trips t ON t.id = e.trip_id
            WHERE t.driver_id IN (:driverIds)
              AND t.status = 'COMPLETED'
              AND e.type = 'DRIVER_ARRIVED'
            GROUP BY t.driver_id
            """, nativeQuery = true)
    List<PunctualityRow> punctualityFor(@Param("driverIds") Collection<UUID> driverIds);

    /** Projection for {@link #punctualityFor}. */
    interface PunctualityRow {
        UUID getDriverId();
        long getOnTime();
        long getTotal();
    }
}
