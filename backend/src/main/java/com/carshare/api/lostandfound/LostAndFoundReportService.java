package com.carshare.api.lostandfound;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.Reservation;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.ReservationStatus;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LostAndFoundReportService {

    private static final Set<ReservationStatus> PARTICIPANT_STATUSES =
            Set.of(ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED);

    private final LostAndFoundReportRepository reports;
    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final UserRepository users;
    private final LostAndFoundHandoverService handovers;
    private final LostAndFoundHandoverRepository handoverRows;

    public LostAndFoundReportService(
            LostAndFoundReportRepository reports,
            TripRepository trips,
            ReservationRepository reservations,
            UserRepository users,
            LostAndFoundHandoverService handovers,
            LostAndFoundHandoverRepository handoverRows) {
        this.reports = reports;
        this.trips = trips;
        this.reservations = reservations;
        this.users = users;
        this.handovers = handovers;
        this.handoverRows = handoverRows;
    }

    @Transactional(readOnly = true)
    public List<TripOption> listTrips(UUID userId) {
        var drivenTrips = trips.findByDriver_IdOrderByDepartureTimeDesc(userId);
        var bookedTrips = reservations
                .findByPassenger_IdAndStatusIn(userId, PARTICIPANT_STATUSES);

        return Stream.concat(
                        drivenTrips.stream(),
                        bookedTrips.stream().map(Reservation::getTrip))
                .map(trip -> new TripOption(
                        trip.getId(), trip.getOriginLabel(),
                        trip.getDestinationLabel(), trip.getDepartureTime()))
                .distinct()
                .sorted(Comparator.comparing(TripOption::departureTime).reversed())
                .toList();
    }

    @Transactional
    public ReportView create(
            UUID userId, UUID tripId, LostAndFoundReport.Type type,
            String title, String description) {
        Trip trip = requireParticipant(userId, tripId);

        if (type == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "report_type_required", "Choose lost or found.");
        }

        String cleanTitle = requireText(title, 100, "Item name");
        String cleanDescription = requireText(description, 1000, "Description");

        AppUser reporter = users.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                        "account_not_found", "Your account could not be found."));

        LostAndFoundReport report = new LostAndFoundReport(
                trip, reporter, type, cleanTitle, cleanDescription);

        return toView(reports.save(report), userId);
    }

    @Transactional(readOnly = true)
    public List<ReportView> listForTrip(UUID userId, UUID tripId) {
        requireParticipant(userId, tripId);
        return reports.findByTrip_IdOrderByCreatedAtDesc(tripId).stream()
                .map(report -> toView(report, userId))
                .toList();
    }

    @Transactional
    public ReportView resolve(UUID userId, UUID reportId) {
        LostAndFoundReport report = reports.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "report_not_found", "Report not found."));

        if (!report.getReporter().getId().equals(userId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_report_author",
                    "Only the author can resolve this report.");
        }

        // A report in a live handover is closed by the finder's code, which closes both sides.
        // Closing it here would leave the other person holding a handover that cannot finish.
        if (handoverRows.existsByLostReport_IdAndStatusIn(
                        reportId, LostAndFoundHandoverService.ACTIVE)
                || handoverRows.existsByFoundReport_IdAndStatusIn(
                        reportId, LostAndFoundHandoverService.ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "handover_in_progress",
                    "This report is in a handover. Finish it with the code, or call it off.");
        }

        report.resolve();
        return toView(report, userId);
    }

    @Transactional
    public ReportView resolveByAdmin(UUID reportId) {
        LostAndFoundReport report = reports.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "report_not_found", "Report not found."));
        handovers.cancelActiveFor(reportId);
        report.resolve();
        return toView(report, report.getReporter().getId());
    }

    private Trip requireParticipant(UUID userId, UUID tripId) {
        Trip trip = trips.findById(tripId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "trip_not_found", "Trip not found."));

        if (trip.isDrivenBy(userId)) {
            return trip;
        }

        boolean isPassenger = reservations
                .findByTrip_IdAndStatusIn(tripId, PARTICIPANT_STATUSES).stream()
                .anyMatch(reservation ->
                        reservation.getPassenger().getId().equals(userId));

        if (!isPassenger) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_trip_participant",
                    "Only trip participants can access these reports.");
        }

        return trip;
    }

    private static String requireText(String value, int maxLength, String label) {
        String clean = value == null ? "" : value.strip();
        if (clean.isEmpty() || clean.length() > maxLength) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_report_text",
                    label + " must contain between 1 and " + maxLength + " characters.");
        }
        return clean;
    }

    private static ReportView toView(LostAndFoundReport report, UUID userId) {
        UUID reporterId = report.getReporter().getId();
        boolean canResolve = report.getStatus() == LostAndFoundReport.Status.OPEN
                && reporterId.equals(userId);

        return new ReportView(
                report.getId(), report.getTrip().getId(), report.getType(),
                report.getTitle(), report.getDescription(), report.getStatus(),
                report.getCreatedAt(), canResolve, reporterId,
                report.getReporter().getFullName());
    }

    public record TripOption(
            UUID id, String origin, String destination, Instant departureTime) {
    }

    public record ReportView(
            UUID id, UUID tripId, LostAndFoundReport.Type type,
            String title, String description, LostAndFoundReport.Status status,
            Instant createdAt, boolean canResolve, UUID reporterId, String reporterName) {

        /** The shape before names were added; the admin list still builds its rows this way. */
        public ReportView(
                UUID id, UUID tripId, LostAndFoundReport.Type type,
                String title, String description, LostAndFoundReport.Status status,
                Instant createdAt, boolean canResolve, UUID reporterId) {
            this(id, tripId, type, title, description, status, createdAt, canResolve,
                    reporterId, null);
        }
    }
}
