package com.carshare.api.reservation;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TripEventRepository extends JpaRepository<TripEvent, UUID> {
    List<TripEvent> findByTrip_IdOrderByCreatedAtAsc(UUID tripId);

    /** The no-show rule measures the wait from the latest DRIVER_ARRIVED event. */
    Optional<TripEvent> findFirstByTrip_IdAndTypeOrderByCreatedAtDesc(UUID tripId,
            TripEventType type);
}
