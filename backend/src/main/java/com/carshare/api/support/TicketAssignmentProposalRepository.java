package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketAssignmentProposalRepository extends JpaRepository<TicketAssignmentProposal, UUID> {
    @EntityGraph(attributePaths = "agent")
    List<TicketAssignmentProposal> findByTicket_IdOrderByCreatedAtDesc(UUID ticketId);
    @EntityGraph(attributePaths = {"agent", "ticket"})
    Optional<TicketAssignmentProposal> findByIdAndTicket_Id(UUID id, UUID ticketId);
}
