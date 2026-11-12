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
@Table(name = "ticket_statements")
public class TicketStatement {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private SupportTicket ticket;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "author_id")
    private AppUser author;
    @Column(name = "statement_text", nullable = false, length = 2000)
    private String statementText;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketStatement() { }

    public TicketStatement(SupportTicket ticket, AppUser author, String statementText) {
        this.id = UUID.randomUUID();
        this.ticket = ticket;
        this.author = author;
        this.statementText = statementText;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public void edit(String text) { statementText = text; }

    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public AppUser getAuthor() { return author; }
    public String getStatementText() { return statementText; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
