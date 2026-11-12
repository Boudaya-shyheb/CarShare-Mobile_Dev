package com.carshare.api.support;

import com.carshare.api.reservation.ReservationStatus;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SupportTicketRepository extends JpaRepository<SupportTicket, UUID> {
    @EntityGraph(attributePaths = {"user", "categoryDefinition", "reportedUser", "assignedAgent"})
    List<SupportTicket> findAllByOrderByCreatedAtDesc();
    @EntityGraph(attributePaths = {"categoryDefinition", "reportedUser", "assignedAgent"})
    List<SupportTicket> findByUser_IdOrderByCreatedAtDesc(UUID userId);
    @EntityGraph(attributePaths = {"user", "categoryDefinition", "reportedUser", "assignedAgent"})
    @Query("""
            select distinct ticket
            from SupportTicket ticket
            where ticket.user.id = :userId
               or ticket.reportedUser.id = :userId
               or ticket.reservationId in (
                    select reservation.id
                    from Reservation reservation
                    where reservation.passenger.id = :userId
                       or reservation.trip.driver.id = :userId
               )
               or (ticket.reservationId is null and ticket.tripId in (
                    select trip.id from Trip trip where trip.driver.id = :userId
               ))
               or (ticket.reservationId is null and ticket.tripId in (
                    select reservation.trip.id
                    from Reservation reservation
                    where reservation.passenger.id = :userId
                      and reservation.status in :participantStatuses
               ))
            order by ticket.createdAt desc
            """)
    List<SupportTicket> findVisibleToUser(
            @Param("userId") UUID userId,
            @Param("participantStatuses") Collection<ReservationStatus> participantStatuses);
    @EntityGraph(attributePaths = {"categoryDefinition", "reportedUser", "assignedAgent"})
    Optional<SupportTicket> findByIdAndUser_Id(UUID id, UUID userId);
    @EntityGraph(attributePaths = {"user", "categoryDefinition", "reportedUser", "assignedAgent"})
    @Query("select t from SupportTicket t where t.id = :id")
    Optional<SupportTicket> findDetailedById(@Param("id") UUID id);
    boolean existsByReservationIdAndCategoryDefinition_Id(UUID reservationId, UUID categoryId);
    long countByCategoryDefinition_Id(UUID categoryId);
}
