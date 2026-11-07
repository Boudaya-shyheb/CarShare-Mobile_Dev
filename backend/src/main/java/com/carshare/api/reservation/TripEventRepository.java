package com.carshare.api.reservation;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TripEventRepository extends JpaRepository<TripEvent, UUID> {
    List<TripEvent> findByTrip_IdOrderByCreatedAtAsc(UUID tripId);
}
