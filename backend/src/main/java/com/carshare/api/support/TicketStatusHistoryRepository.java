package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketStatusHistoryRepository extends JpaRepository<TicketStatusHistory, UUID> {
    @EntityGraph(attributePaths = "changedBy")
    List<TicketStatusHistory> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
}
