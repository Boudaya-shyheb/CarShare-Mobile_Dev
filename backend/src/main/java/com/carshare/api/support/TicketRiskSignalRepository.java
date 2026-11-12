package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TicketRiskSignalRepository extends JpaRepository<TicketRiskSignal, UUID> {
    List<TicketRiskSignal> findByTicket_IdOrderByCreatedAtAsc(UUID ticketId);
    @Modifying(flushAutomatically = true)
    @Query("delete from TicketRiskSignal signal where signal.ticket.id = :ticketId")
    void deleteForTicket(@Param("ticketId") UUID ticketId);
}
