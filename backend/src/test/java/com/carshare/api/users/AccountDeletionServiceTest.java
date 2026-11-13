package com.carshare.api.users;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.auth.AuthSessionRepository;
import com.carshare.api.auth.PasswordResetTokenRepository;
import com.carshare.api.auth.UserAuthIdentityRepository;
import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import com.carshare.api.vehicles.VehicleService;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;

@ExtendWith(MockitoExtension.class)
class AccountDeletionServiceTest {
    private static final Instant NOW = Instant.parse("2026-11-12T12:00:00Z");

    @Mock private UserRepository users;
    @Mock private PasswordEncoder passwordEncoder;
    @Mock private AuthSessionRepository sessions;
    @Mock private PasswordResetTokenRepository resetTokens;
    @Mock private UserAuthIdentityRepository identities;
    @Mock private UserEmergencyContactRepository emergencyContacts;
    @Mock private UserPreferencesRepository preferences;
    @Mock private VehicleService vehicles;
    @Mock private ReservationQueries reservationQueries;

    private AccountDeletionService service;
    private AppUser user;

    @BeforeEach
    void setUp() {
        service = new AccountDeletionService(users, passwordEncoder, sessions, resetTokens, identities,
                emergencyContacts, preferences, vehicles, reservationQueries,
                Clock.fixed(NOW, ZoneOffset.UTC));
        user = new AppUser("Yacine Jomni", "+21612345678", "yacine@carshare.tn", "hash", UserRole.DRIVER);
        user.updateProfilePhoto(new byte[] {1, 2}, "image/png");
        user.submitDriverLicense(LocalDate.of(2030, 1, 1), new byte[] {9}, "image/png");
        user.reviewDriverLicense("APPROVED", null);
        lenient().when(users.findForUpdate(user.getId())).thenReturn(Optional.of(user));
        lenient().when(passwordEncoder.matches("right", "hash")).thenReturn(true);
    }

    private ApiException refused() {
        ApiException error = assertThrows(ApiException.class, () -> service.delete(user.getId(), "right"));
        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        // nothing was touched
        assertEquals("Yacine Jomni", user.getFullName());
        assertNull(user.getAnonymizedAt());
        verifyNoInteractions(sessions, resetTokens, identities, emergencyContacts, preferences, vehicles);
        return error;
    }

    @Test
    @DisplayName("a wrong password is refused and nothing happens")
    void wrongPassword() {
        ApiException error = assertThrows(ApiException.class, () -> service.delete(user.getId(), "wrong"));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals("invalid_password", error.getCode());
        assertNull(user.getAnonymizedAt());
    }

    @Test
    @DisplayName("a banned user cannot delete the account")
    void bannedCannotDelete() {
        user.updateAccountStatus(UserStatus.BANNED, null);

        assertEquals("delete_blocked_banned", refused().getCode());
    }

    @Test
    @DisplayName("a suspended user cannot delete the account, and the end date is returned")
    void suspendedCannotDelete() {
        Instant until = NOW.plus(1, ChronoUnit.DAYS);
        user.updateAccountStatus(UserStatus.SUSPENDED, until);

        ApiException error = refused();

        assertEquals("delete_blocked_suspended", error.getCode());
        assertEquals(until.toString(), error.getProperties().get("statusUntil"));
    }

    @Test
    @DisplayName("a driver with an unfinished trip cannot delete the account")
    void activeTripBlocks() {
        when(reservationQueries.driverHasUnfinishedTrips(user.getId())).thenReturn(true);

        assertEquals("delete_blocked_active_trips", refused().getCode());
    }

    @Test
    @DisplayName("a passenger holding a seat cannot delete the account")
    void activeReservationBlocks() {
        when(reservationQueries.passengerHasActiveReservations(user.getId())).thenReturn(true);

        assertEquals("delete_blocked_active_reservations", refused().getCode());
    }

    @Test
    @DisplayName("an expired suspension no longer blocks deletion")
    void expiredSuspensionDoesNotBlock() {
        user.updateAccountStatus(UserStatus.SUSPENDED, NOW.minus(1, ChronoUnit.HOURS));
        when(passwordEncoder.encode(any())).thenReturn("unusable");

        service.delete(user.getId(), "right");

        assertNotNull(user.getAnonymizedAt());
    }

    @Test
    @DisplayName("deleting anonymises: name, email, phone, photo, licence and password go; the row stays")
    void deleteAnonymises() {
        when(passwordEncoder.encode(any())).thenReturn("unusable");

        service.delete(user.getId(), "right");

        assertEquals("Deleted user", user.getFullName());
        assertTrue(user.getEmail().startsWith("deleted-") && user.getEmail().endsWith("@deleted.carshare.invalid"));
        assertTrue(user.getPhone().startsWith("deleted-"));
        assertEquals("unusable", user.getPasswordHash());
        assertNull(user.getProfilePhoto());
        assertEquals("NOT_SUBMITTED", user.getDriverLicenseStatus());
        assertNull(user.getDriverLicenseExpiry());
        assertNull(user.getDriverLicenseImage());
        assertEquals(NOW, user.getAnonymizedAt());
        // The role and the account status are kept, so sanctions and history still read correctly.
        assertEquals(UserRole.DRIVER, user.getRole());
        verify(users, never()).delete(any(AppUser.class));
    }

    @Test
    @DisplayName("sessions, reset codes, Google identity, contacts, preferences and vehicles are removed")
    void deleteRemovesTheWayBackIn() {
        when(passwordEncoder.encode(any())).thenReturn("unusable");

        service.delete(user.getId(), "right");

        verify(sessions).deleteAllByUser_Id(user.getId());
        verify(resetTokens).deleteForUser(user.getId());
        verify(identities).deleteByUser_Id(user.getId());
        verify(emergencyContacts).deleteByUser_Id(user.getId());
        verify(preferences).deleteById(user.getId());
        verify(vehicles).deleteAllOwnedBy(user.getId());
    }
}
