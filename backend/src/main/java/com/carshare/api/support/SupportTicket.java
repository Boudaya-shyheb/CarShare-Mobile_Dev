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
@Table(name = "support_tickets")
public class SupportTicket {
    public enum Status { OPEN, UNDER_REVIEW, RESOLVED }

    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;
    @Column(name = "trip_id") private UUID tripId;
    @Column(nullable = false, length = 60) private String category;
    @Column(nullable = false, length = 120) private String title;
    @Column(nullable = false, length = 1500) private String description;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private Status status = Status.OPEN;
    @Column(length = 1000) private String resolution;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected SupportTicket() { }

    public SupportTicket(AppUser user, UUID tripId, String category, String title, String description) {
        id = UUID.randomUUID();
        this.user = user;
        this.tripId = tripId;
        this.category = category;
        this.title = title;
        this.description = description;
    }

    @PrePersist void created() { createdAt = Instant.now(); updatedAt = createdAt; }
    @PreUpdate void updated() { updatedAt = Instant.now(); }
    public void review() { if (status == Status.OPEN) status = Status.UNDER_REVIEW; }
    public void resolve(String resolution) { status = Status.RESOLVED; this.resolution = resolution; }

    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public UUID getTripId() { return tripId; }
    public String getCategory() { return category; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public Status getStatus() { return status; }
    public String getResolution() { return resolution; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
