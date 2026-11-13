package com.carshare.api.users;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.common.ApiException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserAccountServiceTest {
    @Mock private UserRepository users;
    @Mock private UserPreferencesRepository preferences;
    @Mock private UserSanctionRepository sanctions;
    @Mock private UserEmergencyContactRepository emergencyContacts;

    private UserAccountService service;
    private AppUser suspended;

    @BeforeEach
    void setUp() {
        service = new UserAccountService(users, preferences, sanctions, emergencyContacts);
        suspended = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.DRIVER);
        suspended.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));
        lenient().when(users.findById(suspended.getId())).thenReturn(Optional.of(suspended));
    }

    // --- licence expiry ------------------------------------------------------------------------

    @Test
    @DisplayName("the daily job expires approved licences using today's date in Tunisia")
    void expiresLicencesPastTheirDate() {
        when(users.expireLicensesBefore(any())).thenReturn(3);

        int expired = service.expireDriverLicenses();

        assertEquals(3, expired);
        verify(users).expireLicensesBefore(LocalDate.now(ZoneId.of("Africa/Tunis")));
    }

    // --- a suspended user cannot change the account --------------------------------------------

    private void refused(Runnable change) {
        ApiException error = assertThrows(ApiException.class, change::run);
        assertEquals("account_suspended", error.getCode());
    }

    @Test
    @DisplayName("a suspended user cannot change preferences, photo, licence or contacts")
    void suspendedCannotChangeTheAccount() {
        refused(() -> service.updatePreferences(suspended.getId(), null));
        refused(() -> service.updatePhoto(suspended.getId(), new byte[] {1}, "image/png"));
        refused(() -> service.deletePhoto(suspended.getId()));
        refused(() -> service.submitDriverLicense(suspended.getId(), LocalDate.now().plusYears(1),
                new byte[] {1}, "image/png"));
        refused(() -> service.addEmergencyContact(suspended.getId(), null));
        refused(() -> service.updateEmergencyContact(suspended.getId(), java.util.UUID.randomUUID(), null));
        refused(() -> service.deleteEmergencyContact(suspended.getId(), java.util.UUID.randomUUID()));

        verifyNoInteractions(preferences, emergencyContacts);
        verify(users, never()).save(any());
    }

    @Test
    @DisplayName("a suspended user can still read their sanctions")
    void suspendedCanStillReadSanctions() {
        when(sanctions.findByUser_IdOrderByIssuedAtDesc(suspended.getId())).thenReturn(java.util.List.of());

        assertEquals(java.util.List.<AuthDtos.Sanction>of(), service.getSanctions(suspended.getId()));
    }
}
