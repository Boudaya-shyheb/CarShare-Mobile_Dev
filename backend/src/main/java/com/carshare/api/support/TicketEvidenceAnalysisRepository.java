package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketEvidenceAnalysisRepository extends JpaRepository<TicketEvidenceAnalysis, UUID> {
    @EntityGraph(attributePaths = {"evidence", "duplicateEvidence"})
    Optional<TicketEvidenceAnalysis> findByEvidence_Id(UUID evidenceId);
    @EntityGraph(attributePaths = {"evidence", "duplicateEvidence"})
    List<TicketEvidenceAnalysis> findByEvidence_Ticket_IdOrderByAnalyzedAtDesc(UUID ticketId);
    @EntityGraph(attributePaths = "evidence")
    Optional<TicketEvidenceAnalysis> findFirstBySha256AndEvidence_IdNot(String sha256, UUID evidenceId);
}
