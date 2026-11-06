package com.carshare.api.users;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserSanctionRepository extends JpaRepository<UserSanction, UUID> {
    List<UserSanction> findByUser_IdOrderByIssuedAtDesc(UUID userId);

    @Query("select coalesce(sum(s.points), 0) from UserSanction s where s.user.id = :userId and s.expiresAt > :now")
    long sumActivePoints(@Param("userId") UUID userId, @Param("now") Instant now);

    @Query("select max(s.issuedAt) from UserSanction s where s.user.id = :userId and s.expiresAt > :now")
    Instant lastActiveSanction(@Param("userId") UUID userId, @Param("now") Instant now);
}
