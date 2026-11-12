package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketEvidenceRepository extends JpaRepository<TicketEvidence, UUID> {
    @EntityGraph(attributePaths = "uploadedBy")
    List<TicketEvidence> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
    Optional<TicketEvidence> findByIdAndTicket_Id(UUID id, UUID ticketId);
}
