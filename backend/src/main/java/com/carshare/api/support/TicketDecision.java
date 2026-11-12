package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_decisions")
public class TicketDecision {
    public enum Result { CONFIRMED, REJECTED, PARTIAL }

    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private SupportTicket ticket;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16) private Result result;
    @Column(nullable = false, length = 1500) private String reason;
    @Column(name = "penalty_points", nullable = false) private short penaltyPoints;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "decided_by")
    private AppUser decidedBy;
    @Column(name = "decided_by_system", nullable = false) private boolean decidedBySystem;
    @Column(name = "decision_number", nullable = false) private short decisionNumber;
    @Column(name = "final_decision", nullable = false) private boolean finalDecision;
    @Column(name = "decided_at", nullable = false) private Instant decidedAt;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketDecision() { }

    public TicketDecision(SupportTicket ticket, Result result, String reason, int penaltyPoints,
            AppUser decidedBy, boolean decidedBySystem, int decisionNumber, boolean finalDecision) {
        this.id = UUID.randomUUID();
        this.ticket = ticket;
        this.result = result;
        this.reason = reason;
        this.penaltyPoints = (short) penaltyPoints;
        this.decidedBy = decidedBy;
        this.decidedBySystem = decidedBySystem;
        this.decisionNumber = (short) decisionNumber;
        this.finalDecision = finalDecision;
        this.decidedAt = Instant.now();
    }

    @PrePersist
    void created() {
        if (decidedAt == null) decidedAt = Instant.now();
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public Result getResult() { return result; }
    public String getReason() { return reason; }
    public int getPenaltyPoints() { return penaltyPoints; }
    public AppUser getDecidedBy() { return decidedBy; }
    public boolean isDecidedBySystem() { return decidedBySystem; }
    public int getDecisionNumber() { return decisionNumber; }
    public boolean isFinalDecision() { return finalDecision; }
    public Instant getDecidedAt() { return decidedAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
