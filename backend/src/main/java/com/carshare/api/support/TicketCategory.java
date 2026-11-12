package com.carshare.api.support;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_categories")
public class TicketCategory {
    public enum Priority { NORMAL, HIGH }
    public enum VerificationType { AUTOMATIC, MANUAL, HYBRID }

    @Id private UUID id;
    @Column(nullable = false, unique = true, length = 60) private String name;
    @Column(nullable = false) private short severity;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 12) private Priority priority;
    @Column(name = "response_delay_hours", nullable = false) private int responseDelayHours;
    @Enumerated(EnumType.STRING)
    @Column(name = "verification_type", nullable = false, length = 16)
    private VerificationType verificationType;
    @Column(nullable = false) private boolean active = true;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketCategory() { }

    public TicketCategory(String name, int severity, Priority priority, int responseDelayHours,
            VerificationType verificationType) {
        this.id = UUID.randomUUID();
        this.name = name;
        this.severity = (short) severity;
        this.priority = priority;
        this.responseDelayHours = responseDelayHours;
        this.verificationType = verificationType;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public void update(String name, int severity, Priority priority, int responseDelayHours,
            VerificationType verificationType) {
        this.name = name;
        this.severity = (short) severity;
        this.priority = priority;
        this.responseDelayHours = responseDelayHours;
        this.verificationType = verificationType;
    }

    public void deactivate() { active = false; }
    public void activate() { active = true; }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public int getSeverity() { return severity; }
    public Priority getPriority() { return priority; }
    public int getResponseDelayHours() { return responseDelayHours; }
    public VerificationType getVerificationType() { return verificationType; }
    public boolean isActive() { return active; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
