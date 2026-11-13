package com.carshare.api.users;

import com.carshare.api.auth.AuthSessionRepository;
import com.carshare.api.auth.PasswordResetTokenRepository;
import com.carshare.api.auth.UserAuthIdentityRepository;
import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import com.carshare.api.vehicles.VehicleService;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Deleting an account.
 *
 * <p>It is refused while the user still has something running (a trip they drive, a seat they
 * hold) and for anybody sanctioned: a banned or currently suspended user cannot wipe their
 * record to escape it. When it is allowed the account is <strong>anonymised, not deleted</strong>:
 * the row stays, so trips, ratings, sanctions and support history keep pointing at somebody
 * ("Deleted user"), while everything personal is replaced or removed.
 */
@Service
public class AccountDeletionService {
    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final AuthSessionRepository sessions;
    private final PasswordResetTokenRepository resetTokens;
    private final UserAuthIdentityRepository identities;
    private final UserEmergencyContactRepository emergencyContacts;
    private final UserPreferencesRepository preferences;
    private final VehicleService vehicles;
    private final ReservationQueries reservationQueries;
    private final Clock clock;

    public AccountDeletionService(UserRepository users, PasswordEncoder passwordEncoder,
            AuthSessionRepository sessions, PasswordResetTokenRepository resetTokens,
            UserAuthIdentityRepository identities, UserEmergencyContactRepository emergencyContacts,
            UserPreferencesRepository preferences, VehicleService vehicles,
            ReservationQueries reservationQueries, Clock clock) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.sessions = sessions;
        this.resetTokens = resetTokens;
        this.identities = identities;
        this.emergencyContacts = emergencyContacts;
        this.preferences = preferences;
        this.vehicles = vehicles;
        this.reservationQueries = reservationQueries;
        this.clock = clock;
    }

    @Transactional
    public void delete(UUID userId, String password) {
        AppUser user = users.findForUpdate(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        if (!passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "invalid_password", "The password is incorrect.");
        }
        Instant now = clock.instant();
        requireDeletable(user, now);

        String tag = user.getId().toString();
        user.anonymize("deleted-" + tag + "@deleted.carshare.invalid", "deleted-" + tag.substring(0, 8),
                passwordEncoder.encode(UUID.randomUUID().toString()), now);
        // Signed out everywhere, and no way back in: no reset code, no Google identity.
        sessions.deleteAllByUser_Id(userId);
        resetTokens.deleteForUser(userId);
        identities.deleteByUser_Id(userId);
        emergencyContacts.deleteByUser_Id(userId);
        preferences.deleteById(userId);
        vehicles.deleteAllOwnedBy(userId);
    }

    private void requireDeletable(AppUser user, Instant now) {
        if (user.getAccountStatus() == UserStatus.BANNED) {
            throw new ApiException(HttpStatus.CONFLICT, "delete_blocked_banned",
                    "A banned account cannot be deleted. Contact CarShare support.");
        }
        if (ActiveUserGuard.isSuspendedAt(user, now)) {
            Instant until = user.getStatusUntil();
            throw new ApiException(HttpStatus.CONFLICT, "delete_blocked_suspended",
                    until == null
                            ? "You cannot delete your account while it is suspended."
                            : "You cannot delete your account while it is suspended, until " + until + ".",
                    until == null ? Map.of() : Map.of("statusUntil", until.toString()));
        }
        if (reservationQueries.driverHasUnfinishedTrips(user.getId())) {
            throw new ApiException(HttpStatus.CONFLICT, "delete_blocked_active_trips",
                    "You still have a trip that has not finished. Finish or cancel it before deleting your account.");
        }
        if (reservationQueries.passengerHasActiveReservations(user.getId())) {
            throw new ApiException(HttpStatus.CONFLICT, "delete_blocked_active_reservations",
                    "You still hold a seat on a trip. Cancel it or ride it before deleting your account.");
        }
    }
}
