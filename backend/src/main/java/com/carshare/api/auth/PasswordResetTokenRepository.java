package com.carshare.api.auth;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface PasswordResetTokenRepository extends JpaRepository<PasswordResetToken, UUID> {
    Optional<PasswordResetToken> findByTokenHashAndExpiresAtAfter(String tokenHash, Instant now);
    Optional<PasswordResetToken> findFirstByUser_EmailAndExpiresAtAfter(String email, Instant now);
    @Modifying
    @Query("delete from PasswordResetToken token where token.user.id = :userId")
    void deleteForUser(@Param("userId") UUID userId);
}
