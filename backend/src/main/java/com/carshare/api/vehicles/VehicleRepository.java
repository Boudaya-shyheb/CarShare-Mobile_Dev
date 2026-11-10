package com.carshare.api.vehicles;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface VehicleRepository extends JpaRepository<Vehicle, UUID> {
    List<Vehicle> findByOwner_IdOrderByCreatedAtDesc(UUID ownerId);
    Optional<Vehicle> findByIdAndOwner_Id(UUID id, UUID ownerId);
    Optional<Vehicle> findByOwner_IdAndDefaultVehicleTrue(UUID ownerId);
    boolean existsByRegistrationNumber(String registrationNumber);
    boolean existsByRegistrationNumberAndIdNot(String registrationNumber, UUID vehicleId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select v from Vehicle v where v.id = :id and v.owner.id = :ownerId")
    Optional<Vehicle> findOwnedForUpdate(@Param("id") UUID id, @Param("ownerId") UUID ownerId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select v from Vehicle v where v.id = :id")
    Optional<Vehicle> findForUpdate(@Param("id") UUID id);

    @Query("""
            select v from Vehicle v
            where v.owner.id = :ownerId and v.status = com.carshare.api.vehicles.Vehicle.Status.ACTIVE
            order by case when v.lastUsedAt is null then 1 else 0 end, v.lastUsedAt desc, v.createdAt desc
            """)
    List<Vehicle> findActiveForDefault(@Param("ownerId") UUID ownerId);
}
