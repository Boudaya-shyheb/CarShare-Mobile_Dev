package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_assignment_proposals")
public class TicketAssignmentProposal {
    public enum Status { PROPOSED, CONFIRMED, REJECTED }
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false) private SupportTicket ticket;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "agent_id", nullable = false) private AppUser agent;
    @Column(nullable = false, length = 30) private String algorithm;
    @Column(nullable = false) private int score;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private Status status;
    @Column(nullable = false, length = 500) private String explanation;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "confirmed_at") private Instant confirmedAt;

    protected TicketAssignmentProposal() { }
    public TicketAssignmentProposal(SupportTicket ticket, AppUser agent, String algorithm,
            int score, String explanation) {
        id = UUID.randomUUID(); this.ticket = ticket; this.agent = agent;
        this.algorithm = algorithm; this.score = score; this.explanation = explanation;
        status = Status.PROPOSED; createdAt = Instant.now();
    }
    public void confirm() { status = Status.CONFIRMED; confirmedAt = Instant.now(); }
    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public AppUser getAgent() { return agent; }
    public String getAlgorithm() { return algorithm; }
    public int getScore() { return score; }
    public Status getStatus() { return status; }
    public String getExplanation() { return explanation; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getConfirmedAt() { return confirmedAt; }
}
