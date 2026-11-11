package com.carshare.api.lostandfound;

import com.carshare.api.reservation.Trip;
import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "lost_and_found_reports")
public class LostAndFoundReport {

    public enum Type {
        LOST, FOUND
    }

    public enum Status {
        OPEN, RESOLVED
    }

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "reporter_id", nullable = false)
    private AppUser reporter;

    @Enumerated(EnumType.STRING)
    @Column(name = "report_type", nullable = false, length = 10)
    private Type type;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(nullable = false, length = 1000)
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Status status;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected LostAndFoundReport() {
    }

    public LostAndFoundReport(
            Trip trip, AppUser reporter, Type type,
            String title, String description) {
        this.id = UUID.randomUUID();
        this.trip = trip;
        this.reporter = reporter;
        this.type = type;
        this.title = title;
        this.description = description;
        this.status = Status.OPEN;
        this.createdAt = Instant.now();
    }

    public UUID getId() { return id; }
    public Trip getTrip() { return trip; }
    public AppUser getReporter() { return reporter; }
    public Type getType() { return type; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public Status getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }

    public void resolve() {
        status = Status.RESOLVED;
    }
}