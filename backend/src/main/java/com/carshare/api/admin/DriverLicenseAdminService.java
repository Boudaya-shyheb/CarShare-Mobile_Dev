package com.carshare.api.admin;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DriverLicenseAdminService {
    private final UserRepository users;
    public DriverLicenseAdminService(UserRepository users) { this.users = users; }

    @Transactional(readOnly = true)
    public List<LicenseReview> pending() {
        return users.findByRoleAndDriverLicenseStatusOrderByCreatedAtDesc(UserRole.DRIVER, "PENDING_REVIEW")
                .stream().map(LicenseReview::from).toList();
    }

    @Transactional(readOnly = true)
    public LicenseImage image(UUID userId) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "driver_not_found", "Driver account not found."));
        if (!"PENDING_REVIEW".equals(user.getDriverLicenseStatus())) throw new ApiException(HttpStatus.NOT_FOUND,
                "license_not_pending", "This license is no longer waiting for review.");
        if (user.getDriverLicenseImage() == null) throw new ApiException(HttpStatus.NOT_FOUND,
                "driver_license_image_not_found", "The license image is no longer available.");
        return new LicenseImage(user.getDriverLicenseImage(), user.getDriverLicenseContentType());
    }

    @Transactional
    public LicenseReview review(UUID userId, ReviewRequest request) {
        AppUser user = requirePending(userId);
        if (!"APPROVED".equals(request.status()) && !"REJECTED".equals(request.status()))
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_license_decision", "Choose approve or reject.");
        String reason = request.reason() == null ? "" : request.reason().strip();
        if ("REJECTED".equals(request.status()) && reason.isBlank())
            throw new ApiException(HttpStatus.BAD_REQUEST, "license_reason_required", "Add a reason when rejecting a license.");
        user.reviewDriverLicense(request.status(), reason.isBlank() ? null : reason);
        return LicenseReview.from(user);
    }

    private AppUser requirePending(UUID id) {
        AppUser user = users.findForUpdate(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "driver_not_found", "Driver account not found."));
        if (!"PENDING_REVIEW".equals(user.getDriverLicenseStatus())) throw new ApiException(HttpStatus.NOT_FOUND,
                "license_not_pending", "This license is no longer waiting for review.");
        return user;
    }

    public record ReviewRequest(String status, String reason) { }
    public record LicenseImage(byte[] bytes, String contentType) { }
    public record LicenseReview(UUID userId, String fullName, String email, String phone,
            LocalDate expiryDate, String status, String reviewReason) {
        static LicenseReview from(AppUser user) {
            return new LicenseReview(user.getId(), user.getFullName(), user.getEmail(), user.getPhone(),
                    user.getDriverLicenseExpiry(), user.getDriverLicenseStatus(), user.getDriverLicenseReviewReason());
        }
    }
}
