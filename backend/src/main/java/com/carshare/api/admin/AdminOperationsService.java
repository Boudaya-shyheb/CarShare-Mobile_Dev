package com.carshare.api.admin;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.common.ApiException;
import com.carshare.api.lostandfound.LostAndFoundReportRepository;
import com.carshare.api.lostandfound.LostAndFoundReportService;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.reservation.TripStatus;
import com.carshare.api.support.SupportService;
import com.carshare.api.support.SupportTicket;
import com.carshare.api.support.SupportTicketRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserAccountService;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserSanction;
import com.carshare.api.users.UserSanctionRepository;
import com.carshare.api.vehicles.Vehicle;
import com.carshare.api.vehicles.VehiclePhoto;
import com.carshare.api.vehicles.VehicleRepository;
import java.time.Instant;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AdminOperationsService {
    /** The most trips one call may return, whatever limit is asked for. */
    static final int MAX_TRIPS = 500;

    private final VehicleRepository vehicles;
    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final LostAndFoundReportRepository lostReports;
    private final LostAndFoundReportService lostAndFound;
    private final SupportTicketRepository tickets;
    private final UserRepository users;
    private final UserSanctionRepository sanctions;
    private final UserAccountService accounts;

    public AdminOperationsService(VehicleRepository vehicles, TripRepository trips,
            ReservationRepository reservations, LostAndFoundReportRepository lostReports,
            LostAndFoundReportService lostAndFound, SupportTicketRepository tickets,
            UserRepository users, UserSanctionRepository sanctions, UserAccountService accounts) {
        this.vehicles = vehicles;
        this.trips = trips;
        this.reservations = reservations;
        this.lostReports = lostReports;
        this.lostAndFound = lostAndFound;
        this.tickets = tickets;
        this.users = users;
        this.sanctions = sanctions;
        this.accounts = accounts;
    }

    @Transactional(readOnly = true)
    public List<AdminVehicle> vehicles() {
        return vehicles.findAllByOrderByCreatedAtDesc().stream().map(AdminVehicle::from).toList();
    }

    @Transactional
    public AdminVehicle reviewVehicle(UUID vehicleId, ReviewVehicleRequest request) {
        Vehicle vehicle = vehicles.findForUpdate(vehicleId).orElseThrow(() -> notFound("vehicle_not_found", "Vehicle not found."));
        Vehicle.ReviewStatus status = request.status();
        if (status == null || status == Vehicle.ReviewStatus.PENDING) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_review_status", "Choose approve or reject.");
        }
        String reason = request.reason() == null ? "" : request.reason().strip();
        if (status == Vehicle.ReviewStatus.REJECTED && reason.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "review_reason_required", "A reason is required when rejecting a vehicle.");
        }
        vehicle.review(status, reason.isBlank() ? null : reason);
        return AdminVehicle.from(vehicle);
    }

    /** Newest departure first. [status] keeps one status (null, blank or "all" keeps every one). */
    @Transactional(readOnly = true)
    public List<AdminTrip> trips(String status, int limit) {
        int size = Math.min(Math.max(limit, 1), MAX_TRIPS);
        return trips.findByStatusInOrderByDepartureTimeDesc(tripStatuses(status), PageRequest.of(0, size))
                .stream().map(AdminTrip::from).toList();
    }

    private static Set<TripStatus> tripStatuses(String status) {
        if (status == null || status.isBlank() || status.trim().equalsIgnoreCase("all")) {
            return EnumSet.allOf(TripStatus.class);
        }
        try {
            return EnumSet.of(TripStatus.valueOf(status.trim().toUpperCase(Locale.ROOT)));
        } catch (IllegalArgumentException invalid) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_status", "Choose a valid trip status.");
        }
    }

    @Transactional(readOnly = true)
    public List<AdminReservation> reservations() {
        return reservations.findAllByOrderByCreatedAtDesc().stream().map(AdminReservation::from).toList();
    }

    @Transactional(readOnly = true)
    public List<com.carshare.api.lostandfound.LostAndFoundReportService.ReportView> lostAndFound() {
        return lostReports.findAllByOrderByCreatedAtDesc().stream()
                .map(report -> new com.carshare.api.lostandfound.LostAndFoundReportService.ReportView(
                        report.getId(), report.getTrip().getId(), report.getType(), report.getTitle(),
                        report.getDescription(), report.getStatus(), report.getCreatedAt(), false,
                        report.getReporter().getId(), report.getReporter().getFullName(),
                        report.getTrip().getOriginLabel(), report.getTrip().getDestinationLabel(),
                        report.getTrip().getDepartureTime()))
                .toList();
    }

    @Transactional
    public com.carshare.api.lostandfound.LostAndFoundReportService.ReportView resolveLostReport(UUID id) {
        return lostAndFound.resolveByAdmin(id);
    }

    @Transactional(readOnly = true)
    public List<SupportService.TicketView> tickets() {
        return tickets.findAllByOrderByCreatedAtDesc().stream().map(SupportService.TicketView::from).toList();
    }

    @Transactional
    public SupportService.TicketView updateTicket(UUID id, UpdateTicketRequest request) {
        SupportTicket ticket = tickets.findById(id).orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
        if (request.status() == SupportTicket.Status.UNDER_REVIEW) {
            ticket.review();
        } else if (request.status() == SupportTicket.Status.RESOLVED) {
            String resolution = request.resolution() == null ? "" : request.resolution().strip();
            if (resolution.isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST,
                    "resolution_required", "Add a resolution before closing this request.");
            ticket.resolve(resolution);
        } else {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_ticket_status", "Choose under review or resolved.");
        }
        return SupportService.TicketView.from(ticket);
    }

    @Transactional(readOnly = true)
    public List<AdminSanction> sanctions() {
        Instant now = Instant.now();
        return sanctions.findAll().stream().sorted((a, b) -> b.getIssuedAt().compareTo(a.getIssuedAt()))
                .map(sanction -> AdminSanction.from(sanction, now)).toList();
    }

    @Transactional
    public AdminSanction createSanction(UUID adminId, UUID userId, CreateSanctionRequest request) {
        AppUser target = users.findForUpdate(userId).orElseThrow(() -> notFound("user_not_found", "User account not found."));
        if (adminId.equals(userId)) throw new ApiException(HttpStatus.BAD_REQUEST,
                "cannot_sanction_self", "An administrator cannot issue a sanction to their own account.");
        if (target.getRole() == com.carshare.api.users.UserRole.ADMIN) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "cannot_sanction_admin", "Administrator accounts cannot receive user sanctions.");
        }
        if (request.points() != 1 && request.points() != 3 && request.points() != 6) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_sanction_points", "Choose 1, 3, or 6 points.");
        }
        String reason = request.reason() == null ? "" : request.reason().strip();
        if (reason.isBlank() || reason.length() > 500) throw new ApiException(HttpStatus.BAD_REQUEST,
                "sanction_reason_required", "A reason of 1 to 500 characters is required.");
        UserSanction sanction = sanctions.save(new UserSanction(target, request.points(), reason));
        accounts.refreshStatus(target, Instant.now());
        return AdminSanction.from(sanction, Instant.now());
    }

    private static ApiException notFound(String code, String message) {
        return new ApiException(HttpStatus.NOT_FOUND, code, message);
    }

    public record ReviewVehicleRequest(Vehicle.ReviewStatus status, String reason) { }
    public record UpdateTicketRequest(SupportTicket.Status status, String resolution) { }
    public record CreateSanctionRequest(int points, String reason) { }

    public record AdminVehicle(UUID id, UUID ownerId, String ownerName, String ownerEmail,
            String brand, String model, int year, String color, String registrationNumber,
            int seats, Vehicle.Status vehicleStatus, Vehicle.ReviewStatus reviewStatus,
            String reviewReason, java.time.LocalDate insuranceExpiryDate,
            java.time.LocalDate inspectionExpiryDate, Instant createdAt, List<VehiclePhotoView> photos) {
        static AdminVehicle from(Vehicle v) {
            return new AdminVehicle(v.getId(), v.getOwner().getId(), v.getOwner().getFullName(), v.getOwner().getEmail(),
                    v.getBrand(), v.getModel(), v.getYear(), v.getColor(), v.getRegistrationNumber(), v.getSeatsNumber(),
                    v.getStatus(), v.getReviewStatus(), v.getReviewReason(), v.getInsuranceExpiryDate(),
                    v.getInspectionExpiryDate(), v.getCreatedAt(), v.getPhotos().stream().map(VehiclePhotoView::from).toList());
        }
    }
    public record VehiclePhotoView(UUID id, boolean primary, String mimeType) {
        static VehiclePhotoView from(VehiclePhoto p) { return new VehiclePhotoView(p.getId(), p.isPrimaryPhoto(), p.getMimeType()); }
    }
    public record AdminTrip(UUID id, UUID driverId, String driverName, String origin, String destination,
            Instant departureTime, String status, boolean incidentReported, UUID vehicleId,
            String cancelReason, Instant createdAt) {
        static AdminTrip from(com.carshare.api.reservation.Trip t) {
            return new AdminTrip(t.getId(), t.getDriver().getId(), t.getDriver().getFullName(),
                    t.getOriginLabel(), t.getDestinationLabel(), t.getDepartureTime(), t.getStatus().name(),
                    t.isDeviating(), t.getVehicleId(), t.getCancelReason(), t.getCreatedAt());
        }
    }
    public record AdminReservation(UUID id, UUID tripId, String origin, String destination,
            String driverName, String passengerName, int seats, String status, String cancelReason,
            boolean lateCancellation, boolean checkedIn, Instant createdAt) {
        static AdminReservation from(com.carshare.api.reservation.Reservation r) {
            return new AdminReservation(r.getId(), r.getTrip().getId(), r.getTrip().getOriginLabel(),
                    r.getTrip().getDestinationLabel(), r.getTrip().getDriver().getFullName(),
                    r.getPassenger().getFullName(), r.getSeats(), r.getStatus().name(), r.getCancelReason(),
                    r.isLateCancellation(), r.isCheckedIn(), r.getCreatedAt());
        }
    }
    public record AdminSanction(UUID id, UUID userId, String userName, String userEmail, int points,
            String reason, Instant issuedAt, Instant expiresAt, boolean active, String accountStatus) {
        static AdminSanction from(UserSanction s, Instant now) {
            return new AdminSanction(s.getId(), s.getUser().getId(), s.getUser().getFullName(),
                    s.getUser().getEmail(), s.getPoints(), s.getReason(), s.getIssuedAt(), s.getExpiresAt(),
                    s.getExpiresAt().isAfter(now), s.getUser().getAccountStatus().name());
        }
    }
}
