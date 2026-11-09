package com.carshare.api.reservation;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;

/**
 * One GPS fix sent by the driver's phone. Append-only, so the finished trip can be replayed
 * (step 10). The only identifier that is not a UUID in this schema: these rows arrive in bulk and
 * nothing outside the module refers to one, so the migration gives them a BIGSERIAL.
 */
@Entity
@Table(name = "gps_points")
public class GpsPoint {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @Column(nullable = false) private double lat;
    @Column(nullable = false) private double lng;

    // REAL in the migration, so the field is a float; null when the phone had no speed reading.
    @Column(name = "speed_mps") private Float speedMps;

    /** When the phone took the fix, which is not when the server received it. */
    @Column(name = "recorded_at", nullable = false) private Instant recordedAt;

    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected GpsPoint() { }

    public GpsPoint(Trip trip, double lat, double lng, Float speedMps, Instant recordedAt) {
        this.trip = trip;
        this.lat = lat;
        this.lng = lng;
        this.speedMps = speedMps;
        this.recordedAt = recordedAt;
    }

    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }

    public Long getId() { return id; }
    public Trip getTrip() { return trip; }
    public double getLat() { return lat; }
    public double getLng() { return lng; }
    public Float getSpeedMps() { return speedMps; }
    public Instant getRecordedAt() { return recordedAt; }
    public Instant getCreatedAt() { return createdAt; }
}
