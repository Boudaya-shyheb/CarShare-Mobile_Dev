package com.carshare.api.support;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class TicketSlaScheduler {
    private static final List<SupportTicket.Status> ACTIVE = List.of(
            SupportTicket.Status.OPEN, SupportTicket.Status.AWAITING_RESPONSE,
            SupportTicket.Status.UNDER_REVIEW, SupportTicket.Status.CONTESTED);
    private final SupportTicketRepository tickets;
    private final TicketPriorityService priority;
    private final TicketEscalationEventRepository events;

    public TicketSlaScheduler(SupportTicketRepository tickets, TicketPriorityService priority,
            TicketEscalationEventRepository events) {
        this.tickets = tickets; this.priority = priority; this.events = events;
    }

    @Scheduled(fixedDelayString = "${carshare.support.sla-check-ms:900000}")
    @Transactional
    public void check() {
        Instant now = Instant.now();
        for (SupportTicket ticket : tickets.findByStatusIn(ACTIVE)) {
            priority.refresh(ticket);
            long minutes = Duration.between(now, ticket.getDeadline()).toMinutes();
            if (minutes < 0) add(ticket, "OVERDUE:" + ticket.getDeadline(),
                    TicketEscalationEvent.Type.OVERDUE, "The support SLA deadline has passed.");
            else if (minutes <= 360) add(ticket, "NEAR:" + ticket.getDeadline(),
                    TicketEscalationEvent.Type.NEAR_DEADLINE,
                    "The support SLA deadline is less than six hours away.");
            if (ticket.getCreatedAt().plusSeconds(48 * 3600L).isBefore(now)
                    && ticket.getStatus() == SupportTicket.Status.AWAITING_RESPONSE) {
                add(ticket, "NO_RESPONSE:" + ticket.getCreatedAt(),
                        TicketEscalationEvent.Type.NO_RESPONSE,
                        "No participant response was recorded within 48 hours.");
            }
            if (ticket.getAssignedAgent() == null) add(ticket, "UNASSIGNED:" + ticket.getCreatedAt(),
                    TicketEscalationEvent.Type.UNASSIGNED, "The ticket has no assigned agent.");
        }
    }

    private void add(SupportTicket ticket, String suffix, TicketEscalationEvent.Type type,
            String message) {
        String key = ticket.getId() + ":" + suffix;
        if (!events.existsByEventKey(key)) {
            events.save(new TicketEscalationEvent(ticket, key, type, message));
        }
    }
}
