package com.carshare.api.lostandfound;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface LostAndFoundReportRepository
        extends JpaRepository<LostAndFoundReport, UUID> {

    @EntityGraph(attributePaths = {"trip", "reporter"})
    List<LostAndFoundReport> findAllByOrderByCreatedAtDesc();

    List<LostAndFoundReport> findByTrip_IdOrderByCreatedAtDesc(UUID tripId);
}
