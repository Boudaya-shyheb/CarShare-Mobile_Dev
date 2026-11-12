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
import java.math.BigDecimal;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

@Entity
@Table(name = "support_tickets")
public class SupportTicket {
    public enum Status {
        OPEN,
        AWAITING_RESPONSE,
        UNDER_REVIEW,
        RESOLVED,
        CLOSED,
        WITHDRAWN,
        CONTESTED
    }

    @Id private UUID id;
    @Column(nullable = false, unique = true, length = 24) private String reference;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private AppUser user;
    @Column(name = "trip_id") private UUID tripId;
    @Column(name = "reservation_id") private UUID reservationId;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reported_user_id")
    private AppUser reportedUser;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "category_id", nullable = false)
    private TicketCategory categoryDefinition;
    // Kept for compatibility with tickets created before migration V17.
    @Column(nullable = false, length = 60) private String category;
    @Column(nullable = false, length = 120) private String title;
    @Column(nullable = false, length = 1500) private String description;
    @Column(name = "priority_score", nullable = false, precision = 10, scale = 2)
    private BigDecimal priorityScore = BigDecimal.ZERO;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20) private Status status = Status.OPEN;
    @Column(length = 1000) private String resolution;
    @Column(nullable = false) private Instant deadline;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "grouped_case_id")
    private SupportTicket groupedCase;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assigned_agent_id")
    private AppUser assignedAgent;
    @Column(name = "withdrawn_at") private Instant withdrawnAt;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected SupportTicket() { }

    public SupportTicket(AppUser user, UUID tripId, UUID reservationId, AppUser reportedUser,
            TicketCategory category, String title, String description) {
        this.id = UUID.randomUUID();
        this.user = user;
        this.tripId = tripId;
        this.reservationId = reservationId;
        this.reportedUser = reportedUser;
        this.categoryDefinition = category;
        this.category = category.getName();
        this.title = title;
        this.description = description;
        this.deadline = Instant.now().plusSeconds(category.getResponseDelayHours() * 3600L);
    }

    public SupportTicket(AppUser user, UUID tripId, TicketCategory category, String title,
            String description) {
        this(user, tripId, null, null, category, title, description);
    }

    @PrePersist
    void created() {
        Instant now = Instant.now();
        if (id == null) id = UUID.randomUUID();
        if (reference == null) {
            int year = now.atZone(ZoneOffset.UTC).getYear();
            reference = "DSP-" + year + "-" + id.toString().replace("-", "")
                    .substring(0, 8).toUpperCase();
        }
        if (deadline == null) deadline = now.plusSeconds(72 * 3600L);
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public void review() {
        moveTo(Status.UNDER_REVIEW);
    }

    public void resolve(String resolution) {
        moveTo(Status.RESOLVED);
        this.resolution = resolution;
    }

    public void awaitResponse() { moveTo(Status.AWAITING_RESPONSE); }
    public void close() { moveTo(Status.CLOSED); }
    public void contest() { moveTo(Status.CONTESTED); }

    public void updateOpen(TicketCategory category, String title, String description) {
        if (status != Status.OPEN) {
            throw new IllegalStateException("Only an open ticket can be updated.");
        }
        this.categoryDefinition = category;
        this.category = category.getName();
        this.title = title;
        this.description = description;
        this.deadline = createdAt.plusSeconds(category.getResponseDelayHours() * 3600L);
    }

    public void withdraw() {
        moveTo(Status.WITHDRAWN);
        withdrawnAt = Instant.now();
    }

    public void moveTo(Status next) {
        boolean allowed = switch (status) {
            case OPEN -> next == Status.AWAITING_RESPONSE || next == Status.RESOLVED
                    || next == Status.WITHDRAWN || next == Status.UNDER_REVIEW;
            case AWAITING_RESPONSE -> next == Status.UNDER_REVIEW || next == Status.RESOLVED;
            case UNDER_REVIEW -> next == Status.RESOLVED;
            case RESOLVED -> next == Status.CLOSED || next == Status.CONTESTED;
            case CONTESTED -> next == Status.UNDER_REVIEW;
            case CLOSED, WITHDRAWN -> false;
        };
        if (!allowed) {
            throw new IllegalStateException(
                    "A ticket cannot move from " + status + " to " + next + ".");
        }
        status = next;
    }

    public UUID getId() { return id; }
    public String getReference() { return reference; }
    public AppUser getUser() { return user; }
    public UUID getTripId() { return tripId; }
    public UUID getReservationId() { return reservationId; }
    public AppUser getReportedUser() { return reportedUser; }
    public TicketCategory getCategoryDefinition() { return categoryDefinition; }
    public String getCategory() { return category; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public BigDecimal getPriorityScore() { return priorityScore; }
    public Status getStatus() { return status; }
    public String getResolution() { return resolution; }
    public Instant getDeadline() { return deadline; }
    public SupportTicket getGroupedCase() { return groupedCase; }
    public AppUser getAssignedAgent() { return assignedAgent; }
    public Instant getWithdrawnAt() { return withdrawnAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
