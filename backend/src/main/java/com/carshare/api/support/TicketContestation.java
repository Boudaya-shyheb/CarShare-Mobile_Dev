package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
@Table(name = "ticket_contestations")
public class TicketContestation {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private SupportTicket ticket;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "contested_by")
    private AppUser contestedBy;
    @Column(nullable = false, length = 1000) private String reason;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketContestation() { }

    public TicketContestation(SupportTicket ticket, AppUser contestedBy, String reason) {
        this.id = UUID.randomUUID();
        this.ticket = ticket;
        this.contestedBy = contestedBy;
        this.reason = reason;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public AppUser getContestedBy() { return contestedBy; }
    public String getReason() { return reason; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
