package com.carshare.api.reservation;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface GpsPointRepository extends JpaRepository<GpsPoint, Long> {
    /** The newest fix, whose speed the live view turns into an ETA. */
    Optional<GpsPoint> findFirstByTrip_IdOrderByRecordedAtDesc(UUID tripId);
}
