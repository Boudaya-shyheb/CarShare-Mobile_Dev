package com.carshare.api.lostandfound;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface LostAndFoundHandoverRepository
        extends JpaRepository<LostAndFoundHandover, UUID> {

    /** One handover with both reports and both reporters loaded, for the rules and the view. */
    @Query("""
            select h from LostAndFoundHandover h
            join fetch h.trip
            join fetch h.lostReport lr join fetch lr.reporter
            join fetch h.foundReport fr join fetch fr.reporter
            where h.id = :id
            """)
    Optional<LostAndFoundHandover> findDetailed(@Param("id") UUID id);

    /** Every handover the user is one side of, newest change first. */
    @Query("""
            select h from LostAndFoundHandover h
            join fetch h.trip
            join fetch h.lostReport lr join fetch lr.reporter
            join fetch h.foundReport fr join fetch fr.reporter
            where lr.reporter.id = :userId or fr.reporter.id = :userId
            order by h.updatedAt desc
            """)
    List<LostAndFoundHandover> findAllForUser(@Param("userId") UUID userId);

    Optional<LostAndFoundHandover> findByLostReport_IdAndFoundReport_IdAndStatusIn(
            UUID lostReportId, UUID foundReportId,
            Collection<LostAndFoundHandover.Status> statuses);

    Optional<LostAndFoundHandover> findFirstByLostReport_IdAndFoundReport_IdAndStatusOrderByUpdatedAtDesc(
            UUID lostReportId, UUID foundReportId, LostAndFoundHandover.Status status);

    boolean existsByLostReport_IdAndStatusIn(
            UUID lostReportId, Collection<LostAndFoundHandover.Status> statuses);

    boolean existsByFoundReport_IdAndStatusIn(
            UUID foundReportId, Collection<LostAndFoundHandover.Status> statuses);

    /** Live handovers that hold this report, used when an admin closes the report. */
    @Query("""
            select h from LostAndFoundHandover h
            where (h.lostReport.id = :reportId or h.foundReport.id = :reportId)
              and h.status in :statuses
            """)
    List<LostAndFoundHandover> findForReport(
            @Param("reportId") UUID reportId,
            @Param("statuses") Collection<LostAndFoundHandover.Status> statuses);
}
