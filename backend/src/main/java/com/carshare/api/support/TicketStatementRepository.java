package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketStatementRepository extends JpaRepository<TicketStatement, UUID> {
    @EntityGraph(attributePaths = "author")
    List<TicketStatement> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
    Optional<TicketStatement> findByTicket_IdAndAuthor_Id(UUID ticketId, UUID authorId);
}
