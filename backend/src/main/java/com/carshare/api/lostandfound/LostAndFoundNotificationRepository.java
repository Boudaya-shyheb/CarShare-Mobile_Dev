package com.carshare.api.lostandfound;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface LostAndFoundNotificationRepository
        extends JpaRepository<LostAndFoundNotification, UUID> {

    List<LostAndFoundNotification> findByUser_IdOrderByCreatedAtDesc(UUID userId);

    long countByUser_IdAndReadAtIsNull(UUID userId);

    Optional<LostAndFoundNotification> findByIdAndUser_Id(UUID id, UUID userId);

    @Modifying(clearAutomatically = true)
    @Query("update LostAndFoundNotification n set n.readAt = :now "
            + "where n.user.id = :userId and n.readAt is null")
    int markAllRead(@Param("userId") UUID userId, @Param("now") Instant now);
}
