package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** A banned or suspended user cannot create reports or move a handover along. */
class LostAndFoundAccountRulesTest {
    private final UserRepository users = mock(UserRepository.class);
    private final LostAndFoundReportRepository reports = mock(LostAndFoundReportRepository.class);
    private final LostAndFoundHandoverRepository handoverRows = mock(LostAndFoundHandoverRepository.class);
    private LostAndFoundReportService reportService;
    private LostAndFoundHandoverService handoverService;
    private AppUser user;

    @BeforeEach
    void setUp() {
        handoverService = new LostAndFoundHandoverService(handoverRows, reports, users);
        reportService = new LostAndFoundReportService(reports, mock(TripRepository.class),
                mock(ReservationRepository.class), users, handoverService, handoverRows);
        user = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        when(users.findById(user.getId())).thenReturn(Optional.of(user));
    }

    private void suspend() {
        user.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));
    }

    @Test
    @DisplayName("a suspended user cannot report a lost item")
    void suspendedCannotReport() {
        suspend();

        ApiException error = assertThrows(ApiException.class, () -> reportService.create(user.getId(),
                UUID.randomUUID(), LostAndFoundReport.Type.LOST, "Phone", "Black phone"));

        assertEquals("account_suspended", error.getCode());
        verify(reports, never()).save(any());
    }

    @Test
    @DisplayName("a banned user cannot report")
    void bannedCannotReport() {
        user.updateAccountStatus(UserStatus.BANNED, null);

        ApiException error = assertThrows(ApiException.class, () -> reportService.create(user.getId(),
                UUID.randomUUID(), LostAndFoundReport.Type.FOUND, "Keys", "Silver keys"));

        assertEquals("account_banned", error.getCode());
    }

    @Test
    @DisplayName("a suspended user cannot propose or arrange a handover")
    void suspendedCannotUseHandovers() {
        suspend();

        assertEquals("account_suspended", assertThrows(ApiException.class,
                () -> handoverService.propose(user.getId(), UUID.randomUUID(), UUID.randomUUID())).getCode());
        assertEquals("account_suspended", assertThrows(ApiException.class,
                () -> handoverService.arrange(user.getId(), UUID.randomUUID(), "Here", "Now")).getCode());
        verify(handoverRows, never()).save(any());
    }
}
