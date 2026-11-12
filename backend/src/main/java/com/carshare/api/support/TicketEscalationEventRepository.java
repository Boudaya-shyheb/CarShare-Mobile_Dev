package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketEscalationEventRepository extends JpaRepository<TicketEscalationEvent, UUID> {
    List<TicketEscalationEvent> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
    boolean existsByEventKey(String eventKey);
}
