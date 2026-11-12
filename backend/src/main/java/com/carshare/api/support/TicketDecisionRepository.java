package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TicketDecisionRepository extends JpaRepository<TicketDecision, UUID> {
    @EntityGraph(attributePaths = "decidedBy")
    List<TicketDecision> findByTicket_IdOrderByDecisionNumberAsc(UUID ticketId);
    boolean existsByTicket_IdAndDecisionNumber(UUID ticketId, short decisionNumber);
    @Query("""
            select count(d) from TicketDecision d
            where d.ticket.reportedUser.id = :userId
              and d.result in :results
            """)
    long countInfractions(@Param("userId") UUID userId,
            @Param("results") List<TicketDecision.Result> results);
}
