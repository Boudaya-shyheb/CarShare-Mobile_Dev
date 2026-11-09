package com.carshare.api.reservation;

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

/** Append-only audit row written on every trip status change and tracking alert. */
@Entity
@Table(name = "trip_events")
public class TripEvent {
    @Id private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private TripEventType type;

    // Plain UUID rather than a relation, so the row survives a deleted account.
    @Column(name = "actor_id")
    private UUID actorId;

    @Column private Double lat;
    @Column private Double lng;
    @Column(length = 300) private String detail;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected TripEvent() { }

    public TripEvent(Trip trip, TripEventType type, UUID actorId, Double lat, Double lng, String detail) {
        this.id = UUID.randomUUID();
        this.trip = trip;
        this.type = type;
        this.actorId = actorId;
        this.lat = lat;
        this.lng = lng;
        this.detail = detail;
    }

    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }

    public UUID getId() { return id; }
    public Trip getTrip() { return trip; }
    public TripEventType getType() { return type; }
    public UUID getActorId() { return actorId; }
    public Double getLat() { return lat; }
    public Double getLng() { return lng; }
    public String getDetail() { return detail; }
    public Instant getCreatedAt() { return createdAt; }
}
