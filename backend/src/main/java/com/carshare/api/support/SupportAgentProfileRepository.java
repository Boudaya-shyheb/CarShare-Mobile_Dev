package com.carshare.api.support;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SupportAgentProfileRepository extends JpaRepository<SupportAgentProfile, UUID> {
    @EntityGraph(attributePaths = "user")
    List<SupportAgentProfile> findAllByOrderByUser_FullNameAsc();
}
