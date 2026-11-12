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
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "support_ticket_status_history")
public class TicketStatusHistory {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private SupportTicket ticket;
    @Enumerated(EnumType.STRING)
    @Column(name = "from_status", length = 20)
    private SupportTicket.Status fromStatus;
    @Enumerated(EnumType.STRING)
    @Column(name = "to_status", nullable = false, length = 20)
    private SupportTicket.Status toStatus;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "changed_by")
    private AppUser changedBy;
    @Column(name = "changed_by_system", nullable = false) private boolean changedBySystem;
    @Column(length = 500) private String reason;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketStatusHistory() { }

    public TicketStatusHistory(SupportTicket ticket, SupportTicket.Status fromStatus,
            SupportTicket.Status toStatus, AppUser changedBy, boolean changedBySystem, String reason) {
        this.id = UUID.randomUUID();
        this.ticket = ticket;
        this.fromStatus = fromStatus;
        this.toStatus = toStatus;
        this.changedBy = changedBy;
        this.changedBySystem = changedBySystem;
        this.reason = reason;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public SupportTicket.Status getFromStatus() { return fromStatus; }
    public SupportTicket.Status getToStatus() { return toStatus; }
    public AppUser getChangedBy() { return changedBy; }
    public boolean isChangedBySystem() { return changedBySystem; }
    public String getReason() { return reason; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
