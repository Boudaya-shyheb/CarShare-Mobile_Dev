package com.carshare.api.vehicles;

import com.carshare.api.users.AppUser;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "vehicles")
public class Vehicle {
    public enum TrunkSize { SMALL, MEDIUM, LARGE }
    public enum Status { ACTIVE, INACTIVE, REPORTED }
    public enum ReviewStatus { PENDING, APPROVED, REJECTED }

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "owner_id", nullable = false)
    private AppUser owner;

    @Column(nullable = false, length = 60)
    private String brand;

    @Column(nullable = false, length = 60)
    private String model;

    @Column(name = "manufacturing_year", nullable = false)
    private int year;

    @Column(nullable = false, length = 40)
    private String color;

    @Column(name = "registration_number", nullable = false, length = 12)
    private String registrationNumber;

    @Column(name = "seats_number", nullable = false)
    private int seatsNumber;

    @Enumerated(EnumType.STRING)
    @Column(name = "trunk_size", nullable = false, length = 10)
    private TrunkSize trunkSize;

    @Column(name = "air_conditioning", nullable = false)
    private boolean airConditioning;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private Status status = Status.ACTIVE;

    @Enumerated(EnumType.STRING)
    @Column(name = "review_status", nullable = false, length = 16)
    private ReviewStatus reviewStatus = ReviewStatus.PENDING;

    @Column(name = "review_reason", length = 500)
    private String reviewReason;

    @Column(name = "is_default", nullable = false)
    private boolean defaultVehicle;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "last_used_at")
    private Instant lastUsedAt;

    @Column(name = "insurance_expiry_date")
    private LocalDate insuranceExpiryDate;

    @Column(name = "inspection_expiry_date")
    private LocalDate inspectionExpiryDate;

    @OneToMany(mappedBy = "vehicle", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("createdAt ASC")
    private List<VehiclePhoto> photos = new ArrayList<>();

    protected Vehicle() { }

    public Vehicle(AppUser owner, VehicleDtos.VehicleRequest request, String registrationNumber) {
        id = UUID.randomUUID();
        this.owner = owner;
        update(request, registrationNumber);
    }

    @PrePersist
    void setCreatedAt() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public void update(VehicleDtos.VehicleRequest request, String registrationNumber) {
        brand = request.brand().trim();
        model = request.model().trim();
        year = request.year();
        color = request.color().trim();
        this.registrationNumber = registrationNumber;
        seatsNumber = request.seatsNumber();
        trunkSize = request.trunkSize();
        airConditioning = request.airConditioning();
        insuranceExpiryDate = request.insuranceExpiryDate();
        inspectionExpiryDate = request.inspectionExpiryDate();
        reviewStatus = ReviewStatus.PENDING;
        reviewReason = null;
    }

    public void setDefault(Instant usedAt) {
        defaultVehicle = true;
        lastUsedAt = usedAt;
    }

    public void clearDefault() {
        defaultVehicle = false;
    }

    public void clearReport() {
        if (status == Status.REPORTED) status = Status.ACTIVE;
    }

    public void markReported() {
        status = Status.REPORTED;
    }

    public void review(ReviewStatus reviewStatus, String reason) {
        this.reviewStatus = reviewStatus;
        this.reviewReason = reason;
    }

    public void markUsed(Instant usedAt) {
        lastUsedAt = usedAt;
    }

    public void addPhoto(VehiclePhoto photo) {
        photos.add(photo);
        photo.setVehicle(this);
    }

    public void removePhoto(VehiclePhoto photo) {
        photos.remove(photo);
    }

    public UUID getId() { return id; }
    public AppUser getOwner() { return owner; }
    public String getBrand() { return brand; }
    public String getModel() { return model; }
    public int getYear() { return year; }
    public String getColor() { return color; }
    public String getRegistrationNumber() { return registrationNumber; }
    public int getSeatsNumber() { return seatsNumber; }
    public TrunkSize getTrunkSize() { return trunkSize; }
    public boolean isAirConditioning() { return airConditioning; }
    public Status getStatus() { return status; }
    public ReviewStatus getReviewStatus() { return reviewStatus; }
    public String getReviewReason() { return reviewReason; }
    public boolean isDefaultVehicle() { return defaultVehicle; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getLastUsedAt() { return lastUsedAt; }
    public LocalDate getInsuranceExpiryDate() { return insuranceExpiryDate; }
    public LocalDate getInspectionExpiryDate() { return inspectionExpiryDate; }
    public List<VehiclePhoto> getPhotos() { return photos; }
}
