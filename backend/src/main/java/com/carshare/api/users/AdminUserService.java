package com.carshare.api.users;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AdminUserService {
    private final UserRepository users;
    private final UserAccountService accounts;
    private final ReservationQueries reservationQueries;

    public AdminUserService(UserRepository users, UserAccountService accounts,
            ReservationQueries reservationQueries) {
        this.reservationQueries = reservationQueries;
        this.users = users;
        this.accounts = accounts;
    }

    @Transactional(readOnly = true)
    public List<AuthDtos.AdminUser> listUsers() {
        return users.findAllByOrderByCreatedAtDesc().stream()
                .map(AuthDtos.AdminUser::from)
                .toList();
    }

    @Transactional
    public AuthDtos.AdminUser updateUser(UUID adminId, UUID userId,
            AuthDtos.AdminUpdateUserRequest request) {
        List<AppUser> administrators = users.findAllByRoleForUpdate(UserRole.ADMIN);
        AppUser user = requireUser(userId);
        String email = request.email().trim().toLowerCase(Locale.ROOT);
        users.findByEmail(email).filter(existing -> !existing.getId().equals(userId)).ifPresent(existing -> {
            throw new ApiException(HttpStatus.CONFLICT, "email_in_use",
                    "An account already exists for this email.");
        });

        String phone = normalizePhone(request.phone());
        if (!phone.matches("^\\+?[0-9]{7,15}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_phone", "Enter a valid phone number.");
        }
        if (!phone.equals(normalizePhone(user.getPhone()))
                && users.existsByNormalizedPhoneAndIdNot(phone, userId)) {
            throw new ApiException(HttpStatus.CONFLICT, "phone_in_use",
                    "An account already exists for this phone number.");
        }

        UserRole newRole = UserRole.fromValue(request.role());
        if (user.getRole() == UserRole.ADMIN && newRole != UserRole.ADMIN) {
            if (adminId.equals(userId)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "cannot_change_own_admin_role",
                        "You cannot remove your own administrator role.");
            }
            if (administrators.size() <= 1) {
                throw new ApiException(HttpStatus.CONFLICT, "last_admin",
                        "The last administrator cannot be removed.");
            }
        }

        // The same rule as a driver switching their own account: nobody is left on a trip with a
        // driver who is no longer one.
        if (user.getRole() == UserRole.DRIVER && newRole == UserRole.PASSENGER
                && reservationQueries.driverHasUnfinishedTrips(userId)) {
            throw new ApiException(HttpStatus.CONFLICT, "role_change_active_trips",
                    "This driver has a trip that has not finished, so the account cannot become a "
                            + "passenger yet. The trip has to be finished or cancelled first.");
        }

        String phoneToSave = phone.equals(normalizePhone(user.getPhone()))
                ? user.getPhone() : phone;
        user.updateProfile(request.fullName().trim(), phoneToSave, email, newRole);
        return AuthDtos.AdminUser.from(user);
    }

    @Transactional
    public AuthDtos.AdminUser updateStatus(UUID adminId, UUID userId,
            AuthDtos.AdminStatusRequest request) {
        AppUser user = requireUser(userId);
        UserStatus status = UserStatus.valueOf(request.status());
        Instant now = Instant.now();

        if (user.getRole() == UserRole.ADMIN && status != UserStatus.ACTIVE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "admin_must_remain_active",
                    "Change the administrator role before changing this account status.");
        }
        if (adminId.equals(userId) && status != UserStatus.ACTIVE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "cannot_suspend_self",
                    "You cannot suspend or ban your own account.");
        }
        if (status == UserStatus.SUSPENDED || status == UserStatus.WARNING) {
            if (request.statusUntil() == null || !request.statusUntil().isAfter(now)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_status_expiry",
                        "A warning or suspension must have a future end date.");
            }
        } else if (request.statusUntil() != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_status_expiry",
                    "Active and banned accounts must not have an end date.");
        }

        user.updateAccountStatusByAdmin(status, request.statusUntil(), request.reason().trim());
        if (status == UserStatus.ACTIVE) {
            accounts.refreshStatus(user, now);
        }
        return AuthDtos.AdminUser.from(user);
    }

    private AppUser requireUser(UUID userId) {
        return users.findForUpdate(userId).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                "user_not_found", "User account not found."));
    }

    private String normalizePhone(String phone) {
        return phone.trim().replaceAll("[\\s().-]", "");
    }
}
