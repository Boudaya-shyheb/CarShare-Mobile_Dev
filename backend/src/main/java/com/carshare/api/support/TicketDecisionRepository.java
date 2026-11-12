package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketDecisionRepository extends JpaRepository<TicketDecision, UUID> {
    @EntityGraph(attributePaths = "decidedBy")
    List<TicketDecision> findByTicket_IdOrderByDecisionNumberAsc(UUID ticketId);
    boolean existsByTicket_IdAndDecisionNumber(UUID ticketId, short decisionNumber);
}
