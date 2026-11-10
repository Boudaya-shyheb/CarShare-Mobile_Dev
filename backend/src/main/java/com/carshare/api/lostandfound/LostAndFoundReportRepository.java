package com.carshare.api.lostandfound;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface LostAndFoundReportRepository
        extends JpaRepository<LostAndFoundReport, UUID> {

    List<LostAndFoundReport> findByTrip_IdOrderByCreatedAtDesc(UUID tripId);
}