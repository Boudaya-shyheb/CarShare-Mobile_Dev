package com.carshare.api.support;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketCategoryRepository extends JpaRepository<TicketCategory, UUID> {
    List<TicketCategory> findAllByOrderByNameAsc();
    List<TicketCategory> findByActiveTrueOrderByNameAsc();
    Optional<TicketCategory> findByNameIgnoreCase(String name);
    Optional<TicketCategory> findByNameIgnoreCaseAndActiveTrue(String name);
    boolean existsByNameIgnoreCase(String name);
}
