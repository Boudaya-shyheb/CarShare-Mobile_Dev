package com.carshare.api.reservation;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface GpsPointRepository extends JpaRepository<GpsPoint, Long> {
    /** The newest fix, whose speed the live view turns into an ETA. */
    Optional<GpsPoint> findFirstByTrip_IdOrderByRecordedAtDesc(UUID tripId);

    /**
     * The whole trail in the order the phone recorded it, for the replay on the completion
     * screen. recorded_at rather than id, so a buffer sent late after a dead spot still sits in
     * the right place on the map.
     */
    List<GpsPoint> findByTrip_IdOrderByRecordedAtAsc(UUID tripId);
}
