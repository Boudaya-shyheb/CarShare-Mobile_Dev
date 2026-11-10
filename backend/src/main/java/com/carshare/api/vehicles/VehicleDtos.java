package com.carshare.api.vehicles;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public final class VehicleDtos {
    private VehicleDtos() { }

    public record VehicleRequest(
            @NotBlank @Size(max = 60) String brand,
            @NotBlank @Size(max = 60) String model,
            @Min(1900) @Max(2200) int year,
            @NotBlank @Size(max = 40) String color,
            @NotBlank @Pattern(regexp = "(?i)^(?:\\d{3}\\s*TU\\s*\\d{4}|RS\\s*\\d{6})$") String registrationNumber,
            @Min(1) @Max(9) int seatsNumber,
            @NotNull Vehicle.TrunkSize trunkSize,
            boolean airConditioning,
            LocalDate insuranceExpiryDate,
            LocalDate inspectionExpiryDate) { }

    public record VehicleResponse(
            UUID id,
            String brand,
            String model,
            int year,
            String color,
            String registrationNumber,
            int seatsNumber,
            Vehicle.TrunkSize trunkSize,
            boolean airConditioning,
            Vehicle.Status status,
            boolean defaultVehicle,
            Instant createdAt,
            LocalDate insuranceExpiryDate,
            LocalDate inspectionExpiryDate,
            List<PhotoReference> photos) {
        public static VehicleResponse from(Vehicle vehicle) {
            return new VehicleResponse(
                    vehicle.getId(),
                    vehicle.getBrand(),
                    vehicle.getModel(),
                    vehicle.getYear(),
                    vehicle.getColor(),
                    vehicle.getRegistrationNumber(),
                    vehicle.getSeatsNumber(),
                    vehicle.getTrunkSize(),
                    vehicle.isAirConditioning(),
                    vehicle.getStatus(),
                    vehicle.isDefaultVehicle(),
                    vehicle.getCreatedAt(),
                    vehicle.getInsuranceExpiryDate(),
                    vehicle.getInspectionExpiryDate(),
                    vehicle.getPhotos().stream().map(PhotoReference::from).toList());
        }
    }

    public record PhotoReference(UUID id, String url, String mimeType, boolean primary) {
        public static PhotoReference from(VehiclePhoto photo) {
            return new PhotoReference(
                    photo.getId(),
                    "/vehicles/" + photo.getVehicle().getId() + "/photos/" + photo.getId(),
                    photo.getMimeType(),
                    photo.isPrimaryPhoto());
        }
    }
}
