package com.carshare.api.users;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;
import java.util.UUID;
import java.util.List;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRepository extends JpaRepository<AppUser, UUID> {
    Optional<AppUser> findByEmail(String email);
    boolean existsByEmail(String email);
    @Query(value = "SELECT EXISTS (SELECT 1 FROM app_users WHERE regexp_replace(phone, '[[:space:]().-]', '', 'g') = :phone)", nativeQuery = true)
    boolean existsByNormalizedPhone(@Param("phone") String phone);

    @Query(value = "SELECT EXISTS (SELECT 1 FROM app_users WHERE id <> :id AND regexp_replace(phone, '[[:space:]().-]', '', 'g') = :phone)", nativeQuery = true)
    boolean existsByNormalizedPhoneAndIdNot(@Param("phone") String phone, @Param("id") UUID id);
    List<AppUser> findAllByOrderByCreatedAtDesc();

    /** APPROVED licences whose date has passed become EXPIRED. @return how many were moved */
    @org.springframework.data.jpa.repository.Modifying(clearAutomatically = true)
    @Query("update AppUser u set u.driverLicenseStatus = 'EXPIRED' "
            + "where u.driverLicenseStatus = 'APPROVED' and u.driverLicenseExpiry < :today")
    int expireLicensesBefore(@Param("today") java.time.LocalDate today);
    List<AppUser> findByRoleAndDriverLicenseStatusOrderByCreatedAtDesc(UserRole role, String driverLicenseStatus);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from AppUser u where u.id = :id")
    Optional<AppUser> findForUpdate(@Param("id") UUID id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from AppUser u where u.role = :role order by u.id")
    List<AppUser> findAllByRoleForUpdate(@Param("role") UserRole role);
}
