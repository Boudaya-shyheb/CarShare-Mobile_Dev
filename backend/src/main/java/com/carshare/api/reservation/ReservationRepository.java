package com.carshare.api.reservation;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ReservationRepository extends JpaRepository<Reservation, UUID> {
    @EntityGraph(attributePaths = {"trip", "trip.driver"})
    Optional<Reservation> findByIdAndPassenger_Id(UUID id, UUID passengerId);

    @EntityGraph(attributePaths = {"trip", "trip.driver"})
    List<Reservation> findByPassenger_IdOrderByCreatedAtDesc(UUID passengerId);

    @EntityGraph(attributePaths = {"trip", "trip.driver"})
    List<Reservation> findByPassenger_IdAndStatusInOrderByCreatedAtDesc(UUID passengerId,
            Collection<ReservationStatus> statuses);

    /** Feeds the overlap rule, so the trip of every live reservation is loaded with it. */
    @EntityGraph(attributePaths = "trip")
    List<Reservation> findByPassenger_IdAndStatusIn(UUID passengerId,
            Collection<ReservationStatus> statuses);

    @EntityGraph(attributePaths = {"passenger", "trip"})
    List<Reservation> findByTrip_IdOrderByCreatedAtAsc(UUID tripId);

    @EntityGraph(attributePaths = "trip")
    List<Reservation> findByTrip_IdAndStatusIn(UUID tripId, Collection<ReservationStatus> statuses);

    /** Decides whether a passenger may watch a trip's live position. */
    @EntityGraph(attributePaths = "trip")
    Optional<Reservation> findByTrip_IdAndPassenger_IdAndStatusIn(UUID tripId, UUID passengerId,
            Collection<ReservationStatus> statuses);

    /**
     * Candidates for the auto-refuse job: a reservation nobody answered within the waiting window,
     * or one whose trip is about to leave.
     */
    @Query("""
            select r from Reservation r
            join fetch r.trip t
            where r.status = :status
              and (r.createdAt <= :requestedOnOrBefore or t.departureTime <= :departingOnOrBefore)
            order by r.createdAt asc
            """)
    List<Reservation> findAutoRefusable(@Param("status") ReservationStatus status,
            @Param("requestedOnOrBefore") Instant requestedOnOrBefore,
            @Param("departingOnOrBefore") Instant departingOnOrBefore);
}
