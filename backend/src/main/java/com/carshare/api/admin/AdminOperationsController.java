package com.carshare.api.admin;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.security.SessionPrincipal;
import com.carshare.api.support.SupportService;
import com.carshare.api.vehicles.VehicleService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminOperationsController {
    private final AdminOperationsService admin;
    private final VehicleService vehicles;
    private final DriverLicenseAdminService driverLicenses;

    public AdminOperationsController(AdminOperationsService admin, VehicleService vehicles,
            DriverLicenseAdminService driverLicenses) {
        this.admin = admin;
        this.vehicles = vehicles;
        this.driverLicenses = driverLicenses;
    }

    @GetMapping("/vehicles")
    public List<AdminOperationsService.AdminVehicle> vehicles() { return admin.vehicles(); }

    @PutMapping("/vehicles/{vehicleId}/review")
    public AdminOperationsService.AdminVehicle reviewVehicle(@PathVariable UUID vehicleId,
            @Valid @RequestBody VehicleReviewRequest request) {
        return admin.reviewVehicle(vehicleId, new AdminOperationsService.ReviewVehicleRequest(
                request.status(), request.reason()));
    }

    @GetMapping("/vehicles/{vehicleId}/photos/{photoId}")
    public ResponseEntity<byte[]> vehiclePhoto(@PathVariable UUID vehicleId, @PathVariable UUID photoId) {
        VehicleService.PhotoContent photo = vehicles.getAdminPhoto(vehicleId, photoId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(photo.mimeType()))
                .cacheControl(CacheControl.noStore()).header("X-Content-Type-Options", "nosniff").body(photo.bytes());
    }

    @GetMapping("/driver-licenses")
    public List<DriverLicenseAdminService.LicenseReview> driverLicenses() { return driverLicenses.pending(); }

    @GetMapping("/driver-licenses/{userId}/image")
    public ResponseEntity<byte[]> driverLicenseImage(@PathVariable UUID userId) {
        var image = driverLicenses.image(userId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(image.contentType()))
                .cacheControl(CacheControl.noStore()).header("X-Content-Type-Options", "nosniff").body(image.bytes());
    }

    @PutMapping("/driver-licenses/{userId}/review")
    public DriverLicenseAdminService.LicenseReview reviewDriverLicense(@PathVariable UUID userId,
            @RequestBody DriverLicenseAdminService.ReviewRequest request) {
        return driverLicenses.review(userId, request);
    }

    @GetMapping("/trips")
    public List<AdminOperationsService.AdminTrip> trips() { return admin.trips(); }

    @GetMapping("/reservations")
    public List<AdminOperationsService.AdminReservation> reservations() { return admin.reservations(); }

    @GetMapping("/lost-and-found")
    public List<com.carshare.api.lostandfound.LostAndFoundReportService.ReportView> lostAndFound() {
        return admin.lostAndFound();
    }

    @PutMapping("/lost-and-found/{reportId}/resolve")
    public com.carshare.api.lostandfound.LostAndFoundReportService.ReportView resolveLostReport(
            @PathVariable UUID reportId) { return admin.resolveLostReport(reportId); }

    @GetMapping("/support-tickets")
    public List<SupportService.TicketView> tickets() { return admin.tickets(); }

    @PutMapping("/support-tickets/{ticketId}")
    public SupportService.TicketView updateTicket(@PathVariable UUID ticketId,
            @Valid @RequestBody TicketUpdateRequest request) {
        return admin.updateTicket(ticketId, new AdminOperationsService.UpdateTicketRequest(
                request.status(), request.resolution()));
    }

    @GetMapping("/sanctions")
    public List<AdminOperationsService.AdminSanction> sanctions() { return admin.sanctions(); }

    @PostMapping("/users/{userId}/sanctions")
    public AdminOperationsService.AdminSanction createSanction(
            @AuthenticationPrincipal SessionPrincipal principal, @PathVariable UUID userId,
            @Valid @RequestBody SanctionRequest request) {
        return admin.createSanction(principal.userId(), userId,
                new AdminOperationsService.CreateSanctionRequest(request.points(), request.reason()));
    }

    public record VehicleReviewRequest(com.carshare.api.vehicles.Vehicle.ReviewStatus status, String reason) { }
    public record TicketUpdateRequest(com.carshare.api.support.SupportTicket.Status status,
            String resolution) { }
    public record SanctionRequest(int points, @NotBlank @Size(max = 500) String reason) { }
}
