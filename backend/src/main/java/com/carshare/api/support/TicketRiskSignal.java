package com.carshare.api.support;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_risk_signals")
public class TicketRiskSignal {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false) private SupportTicket ticket;
    @Column(nullable = false, length = 40) private String term;
    @Column(nullable = false, length = 240) private String excerpt;
    @Column(nullable = false) private boolean negated;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected TicketRiskSignal() { }
    public TicketRiskSignal(SupportTicket ticket, String term, String excerpt, boolean negated) {
        id = UUID.randomUUID();
        this.ticket = ticket;
        this.term = term;
        this.excerpt = excerpt;
        this.negated = negated;
        createdAt = Instant.now();
    }
    public UUID getId() { return id; }
    public String getTerm() { return term; }
    public String getExcerpt() { return excerpt; }
    public boolean isNegated() { return negated; }
    public Instant getCreatedAt() { return createdAt; }
}
