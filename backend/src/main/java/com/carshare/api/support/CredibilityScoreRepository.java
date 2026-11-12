package com.carshare.api.support;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CredibilityScoreRepository extends JpaRepository<CredibilityScore, UUID> {
    @EntityGraph(attributePaths = "user")
    Optional<CredibilityScore> findByUser_Id(UUID userId);
}
