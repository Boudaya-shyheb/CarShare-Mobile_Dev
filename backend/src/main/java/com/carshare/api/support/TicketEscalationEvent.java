package com.carshare.api.support;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_escalation_events")
public class TicketEscalationEvent {
    public enum Type { NEAR_DEADLINE, OVERDUE, NO_RESPONSE, UNASSIGNED }
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false) private SupportTicket ticket;
    @Column(name = "event_key", nullable = false, unique = true, length = 180) private String eventKey;
    @Enumerated(EnumType.STRING) @Column(name = "event_type", nullable = false, length = 30)
    private Type type;
    @Column(nullable = false, length = 500) private String message;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected TicketEscalationEvent() { }
    public TicketEscalationEvent(SupportTicket ticket, String eventKey, Type type, String message) {
        id = UUID.randomUUID(); this.ticket = ticket; this.eventKey = eventKey;
        this.type = type; this.message = message; createdAt = Instant.now();
    }
    public UUID getId() { return id; }
    public Type getType() { return type; }
    public String getMessage() { return message; }
    public Instant getCreatedAt() { return createdAt; }
}
