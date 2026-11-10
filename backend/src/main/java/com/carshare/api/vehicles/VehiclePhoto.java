package com.carshare.api.vehicles;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "vehicle_photos")
public class VehiclePhoto {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "vehicle_id", nullable = false)
    private Vehicle vehicle;

    @Column(name = "file_name", nullable = false, unique = true, length = 80)
    private String fileName;

    @Column(name = "mime_type", nullable = false, length = 30)
    private String mimeType;

    @Column(name = "is_primary", nullable = false)
    private boolean primaryPhoto;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected VehiclePhoto() { }

    public VehiclePhoto(String fileName, String mimeType) {
        id = UUID.randomUUID();
        this.fileName = fileName;
        this.mimeType = mimeType;
    }

    @PrePersist
    void setCreatedAt() {
        if (createdAt == null) createdAt = Instant.now();
    }

    void setVehicle(Vehicle vehicle) { this.vehicle = vehicle; }
    void setPrimaryPhoto(boolean primaryPhoto) { this.primaryPhoto = primaryPhoto; }
    public UUID getId() { return id; }
    public Vehicle getVehicle() { return vehicle; }
    public String getFileName() { return fileName; }
    public String getMimeType() { return mimeType; }
    public boolean isPrimaryPhoto() { return primaryPhoto; }
    public Instant getCreatedAt() { return createdAt; }
}
