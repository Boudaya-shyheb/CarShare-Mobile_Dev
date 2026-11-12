package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SupportNotificationRepository
        extends JpaRepository<SupportNotification, UUID> {
    @EntityGraph(attributePaths = "ticket")
    List<SupportNotification> findByUser_IdOrderByCreatedAtDesc(UUID userId);
    Optional<SupportNotification> findByIdAndUser_Id(UUID id, UUID userId);
    long countByUser_IdAndReadAtIsNull(UUID userId);
}
