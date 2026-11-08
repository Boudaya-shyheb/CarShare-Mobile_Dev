package com.carshare.api.reservation;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TripRepository extends JpaRepository<Trip, UUID> {
    @EntityGraph(attributePaths = "driver")
    List<Trip> findByDriver_IdOrderByDepartureTimeDesc(UUID driverId);

    @EntityGraph(attributePaths = "driver")
    List<Trip> findByDriver_IdAndStatusInOrderByDepartureTimeDesc(UUID driverId,
            Collection<TripStatus> statuses);

    @EntityGraph(attributePaths = "driver")
    Optional<Trip> findByIdAndDriver_Id(UUID id, UUID driverId);

    /**
     * Cheap pre-filter for trip search: the hard rules plus a bounding box around both ends of the
     * requested route. TripService then measures the exact haversine distance on the candidates.
     */
    @EntityGraph(attributePaths = "driver")
    @Query("""
            select t from Trip t
            where t.status = :status
              and t.departureTime > :now
              and t.departureTime >= :earliest
              and t.departureTime <= :latest
              and t.seatsAvailable >= :seats
              and t.driver.id <> :searcherId
              and t.originLat >= :originLatMin and t.originLat <= :originLatMax
              and t.originLng >= :originLngMin and t.originLng <= :originLngMax
              and t.destinationLat >= :destinationLatMin and t.destinationLat <= :destinationLatMax
              and t.destinationLng >= :destinationLngMin and t.destinationLng <= :destinationLngMax
            order by t.departureTime asc
            """)
    List<Trip> searchCandidates(@Param("status") TripStatus status,
            @Param("now") Instant now,
            @Param("earliest") Instant earliest,
            @Param("latest") Instant latest,
            @Param("seats") int seats,
            @Param("searcherId") UUID searcherId,
            @Param("originLatMin") double originLatMin,
            @Param("originLatMax") double originLatMax,
            @Param("originLngMin") double originLngMin,
            @Param("originLngMax") double originLngMax,
            @Param("destinationLatMin") double destinationLatMin,
            @Param("destinationLatMax") double destinationLatMax,
            @Param("destinationLngMin") double destinationLngMin,
            @Param("destinationLngMax") double destinationLngMax);

    /**
     * Holds seats for a new reservation. This conditional update is the only thing standing
     * between two passengers and the same last seat: it returns 0 when the seats went to someone
     * else, which the service turns into 409 seats_unavailable.
     *
     * <p>Every method below is a bulk update, so a Trip entity already loaded in the same
     * transaction keeps its old seat counts. Callers must not read seat counts from such an
     * entity afterwards.
     */
    @Modifying(flushAutomatically = true)
    @Query("""
            update Trip t set t.seatsAvailable = t.seatsAvailable - :seats
            where t.id = :tripId and t.seatsAvailable >= :seats
            """)
    int holdSeats(@Param("tripId") UUID tripId, @Param("seats") int seats);

    /** Gives seats back when a reservation is refused, cancelled or auto-refused. */
    @Modifying(flushAutomatically = true)
    @Query("""
            update Trip t set t.seatsAvailable = t.seatsAvailable + :seats
            where t.id = :tripId and t.seatsAvailable + :seats <= t.seatsTotal
            """)
    int releaseSeats(@Param("tripId") UUID tripId, @Param("seats") int seats);

    /** Confirmed seats lock the trip against time, route and price edits. */
    @Modifying(flushAutomatically = true)
    @Query("""
            update Trip t set t.confirmedSeats = t.confirmedSeats + :seats
            where t.id = :tripId and t.confirmedSeats + :seats <= t.seatsTotal
            """)
    int addConfirmedSeats(@Param("tripId") UUID tripId, @Param("seats") int seats);

    @Modifying(flushAutomatically = true)
    @Query("""
            update Trip t set t.confirmedSeats = t.confirmedSeats - :seats
            where t.id = :tripId and t.confirmedSeats >= :seats
            """)
    int releaseConfirmedSeats(@Param("tripId") UUID tripId, @Param("seats") int seats);
}
