package com.carshare.api.users;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserEmergencyContactRepository extends JpaRepository<UserEmergencyContact, UUID> {
    List<UserEmergencyContact> findByUser_IdOrderByName(UUID userId);
    Optional<UserEmergencyContact> findByIdAndUser_Id(UUID id, UUID userId);
}
