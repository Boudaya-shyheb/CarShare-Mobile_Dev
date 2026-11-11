package com.carshare.api.vehicles;

import java.util.Optional;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface VehiclePhotoRepository extends JpaRepository<VehiclePhoto, UUID> {
    Optional<VehiclePhoto> findByIdAndVehicle_Id(UUID id, UUID vehicleId);
    long countByVehicle_Id(UUID vehicleId);
    List<VehiclePhoto> findByVehicle_IdOrderByCreatedAtAsc(UUID vehicleId);
}
