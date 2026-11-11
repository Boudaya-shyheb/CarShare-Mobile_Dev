package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SupportTicketRepository extends JpaRepository<SupportTicket, UUID> {
    @EntityGraph(attributePaths = "user")
    List<SupportTicket> findAllByOrderByCreatedAtDesc();
    List<SupportTicket> findByUser_IdOrderByCreatedAtDesc(UUID userId);
    Optional<SupportTicket> findByIdAndUser_Id(UUID id, UUID userId);
}
