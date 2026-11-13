package com.carshare.api.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import com.carshare.api.security.SecurityProperties;
import com.carshare.api.users.AccountDeletionService;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import java.time.Duration;
import java.time.Instant;
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
class AuthServiceAccountRulesTest {
    @Mock private UserRepository users;
    @Mock private AuthSessionRepository sessions;
    @Mock private PasswordResetTokenRepository resetTokens;
    @Mock private PasswordEncoder passwordEncoder;
    @Mock private ResetMailService resetMailService;
    @Mock private ReservationQueries reservationQueries;
    @Mock private AccountDeletionService accountDeletion;
    @Mock private EmailVerificationService emailVerification;

    private AuthService service;

    @BeforeEach
    void setUp() {
        service = new AuthService(users, sessions, resetTokens, passwordEncoder,
                new SecurityProperties(Duration.ofDays(30), Duration.ofMinutes(30)), resetMailService,
                reservationQueries, accountDeletion, emailVerification);
    }

    private AppUser account(UserRole role) {
        AppUser user = new AppUser("Yacine Jomni", "+21612345678", "yacine@carshare.tn", "hash", role);
        when(users.findById(user.getId())).thenReturn(Optional.of(user));
        return user;
    }

    private AuthDtos.UpdateProfileRequest edit(String role) {
        return new AuthDtos.UpdateProfileRequest("Yacine J.", "+21612345678", "yacine@carshare.tn", role);
    }

    // --- sign-in -------------------------------------------------------------------------------

    private void signsInWithTheRightPassword(AppUser user) {
        when(users.findByEmail("yacine@carshare.tn")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("pw", "hash")).thenReturn(true);
    }

    @Test
    @DisplayName("a banned user cannot sign in, even with the right password, and gets no session")
    void bannedCannotSignIn() {
        AppUser banned = new AppUser("Yacine", "+21612345678", "yacine@carshare.tn", "hash", UserRole.PASSENGER);
        banned.updateAccountStatus(UserStatus.BANNED, null);
        signsInWithTheRightPassword(banned);

        ApiException error = assertThrows(ApiException.class,
                () -> service.signIn(new AuthDtos.SignInRequest("yacine@carshare.tn", "pw")));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("account_banned", error.getCode());
        verify(sessions, never()).save(any());
    }

    @Test
    @DisplayName("a suspended user can sign in")
    void suspendedCanSignIn() {
        AppUser suspended = new AppUser("Yacine", "+21612345678", "yacine@carshare.tn", "hash", UserRole.PASSENGER);
        suspended.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));
        signsInWithTheRightPassword(suspended);

        assertNotNull(service.signIn(new AuthDtos.SignInRequest("yacine@carshare.tn", "pw")));
        verify(sessions).save(any());
    }

    // --- profile edits -------------------------------------------------------------------------

    @Test
    @DisplayName("a suspended user cannot edit the profile")
    void suspendedCannotEditProfile() {
        AppUser user = account(UserRole.PASSENGER);
        user.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));

        ApiException error = assertThrows(ApiException.class, () -> service.updateProfile(user.getId(), edit("passenger")));

        assertEquals("account_suspended", error.getCode());
        assertEquals("Yacine Jomni", user.getFullName());
    }

    // --- role switch ---------------------------------------------------------------------------

    @Test
    @DisplayName("a driver with an unfinished trip cannot become a passenger")
    void driverWithATripCannotSwitch() {
        AppUser driver = account(UserRole.DRIVER);
        when(reservationQueries.driverHasUnfinishedTrips(driver.getId())).thenReturn(true);

        ApiException error = assertThrows(ApiException.class, () -> service.updateProfile(driver.getId(), edit("passenger")));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("role_change_active_trips", error.getCode());
        assertEquals(UserRole.DRIVER, driver.getRole());
    }

    @Test
    @DisplayName("a driver with nothing running can become a passenger")
    void idleDriverCanSwitch() {
        AppUser driver = account(UserRole.DRIVER);
        when(reservationQueries.driverHasUnfinishedTrips(driver.getId())).thenReturn(false);

        service.updateProfile(driver.getId(), edit("passenger"));

        assertEquals(UserRole.PASSENGER, driver.getRole());
    }

    @Test
    @DisplayName("a passenger can always become a driver")
    void passengerCanBecomeDriver() {
        AppUser passenger = account(UserRole.PASSENGER);

        service.updateProfile(passenger.getId(), edit("driver"));

        assertEquals(UserRole.DRIVER, passenger.getRole());
    }

    @Test
    @DisplayName("an administrator keeps the role whatever is sent")
    void adminKeepsTheRole() {
        for (String sent : new String[] {"passenger", "driver", "admin"}) {
            AppUser admin = account(UserRole.ADMIN);

            service.updateProfile(admin.getId(), edit(sent));

            assertEquals(UserRole.ADMIN, admin.getRole(), "after sending " + sent);
            assertEquals("Yacine J.", admin.getFullName());
        }
    }

    @Test
    @DisplayName("nobody can make themselves an administrator")
    void nobodyCanPromoteThemselves() {
        AppUser driver = account(UserRole.DRIVER);

        ApiException error = assertThrows(ApiException.class, () -> service.updateProfile(driver.getId(), edit("admin")));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("role_not_allowed", error.getCode());
        assertEquals(UserRole.DRIVER, driver.getRole());
    }

    @Test
    @DisplayName("editing the profile without changing the email never asks the provider")
    void sameEmailIsNotChecked() {
        AppUser driver = account(UserRole.DRIVER);

        service.updateProfile(driver.getId(), edit("driver"));

        verify(emailVerification, never()).verify(any());
    }

    @Test
    @DisplayName("a new email is checked, and a refused one stops the edit")
    void changedEmailIsChecked() {
        AppUser driver = account(UserRole.DRIVER);
        org.mockito.Mockito.doThrow(new ApiException(HttpStatus.BAD_REQUEST, "email_disposable", "no"))
                .when(emailVerification).verify("new@mailinator.com");

        ApiException error = assertThrows(ApiException.class, () -> service.updateProfile(driver.getId(),
                new AuthDtos.UpdateProfileRequest("Yacine J.", "+21612345678", "New@Mailinator.com", "driver")));

        assertEquals("email_disposable", error.getCode());
    }

    @Test
    @DisplayName("sign-up checks the email last, and a refused one creates no account")
    void signUpIsRefusedForABadEmail() {
        when(users.existsByEmail(any())).thenReturn(false);
        when(users.existsByNormalizedPhone(any())).thenReturn(false);
        org.mockito.Mockito.doThrow(new ApiException(HttpStatus.BAD_REQUEST, "email_undeliverable", "no"))
                .when(emailVerification).verify("test@gmial.com");

        ApiException error = assertThrows(ApiException.class, () -> service.signUp(new AuthDtos.SignUpRequest(
                "Yacine Jomni", "+21612345678", "test@gmial.com", "Passw0rd!x", "Passw0rd!x", "passenger")));

        assertEquals("email_undeliverable", error.getCode());
        verify(users, never()).save(any());
    }
}
