package com.carshare.api.support;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
public interface TicketGeoInvestigationRepository extends JpaRepository<TicketGeoInvestigation, UUID> {
    Optional<TicketGeoInvestigation> findByTicket_Id(UUID ticketId);
}
