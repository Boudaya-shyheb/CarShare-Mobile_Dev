package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketContestationRepository extends JpaRepository<TicketContestation, UUID> {
    @EntityGraph(attributePaths = "contestedBy")
    List<TicketContestation> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
    boolean existsByTicket_IdAndContestedBy_Id(UUID ticketId, UUID userId);
}
