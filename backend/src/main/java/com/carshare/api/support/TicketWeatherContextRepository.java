package com.carshare.api.support;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
public interface TicketWeatherContextRepository extends JpaRepository<TicketWeatherContext, UUID> {
    Optional<TicketWeatherContext> findByTicket_Id(UUID ticketId);
}
