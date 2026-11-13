package com.carshare.api.support;

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

/** A suspended user cannot open or change tickets, statements, evidence or contestations. */
class SupportAccountRulesTest {
    private final UserRepository users = mock(UserRepository.class);
    private final SupportTicketRepository tickets = mock(SupportTicketRepository.class);
    private SupportService service;
    private AppUser user;

    @BeforeEach
    void setUp() {
        service = new SupportService(tickets, users, mock(TripRepository.class),
                mock(ReservationRepository.class), mock(TicketCategoryRepository.class),
                mock(TicketStatusHistoryRepository.class), mock(TicketEvidenceRepository.class),
                mock(TicketStatementRepository.class), mock(TicketDecisionRepository.class),
                mock(TicketContestationRepository.class), mock(SupportNotificationRepository.class),
                mock(SupportEvidenceStorage.class), mock(TicketPriorityService.class));
        user = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        user.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));
        when(users.findById(user.getId())).thenReturn(Optional.of(user));
    }

    private void refused(Runnable action) {
        ApiException error = assertThrows(ApiException.class, action::run);
        assertEquals("account_suspended", error.getCode());
    }

    @Test
    @DisplayName("a suspended user cannot create a ticket")
    void cannotCreateATicket() {
        refused(() -> service.create(user.getId(), new SupportService.TicketRequest(null, null,
                null, null, "Late driver", "He was late")));
        verify(tickets, never()).save(any());
    }

    @Test
    @DisplayName("a suspended user cannot edit a ticket, add evidence, or write or edit a statement")
    void cannotChangeATicket() {
        UUID ticketId = UUID.randomUUID();
        refused(() -> service.update(user.getId(), ticketId, new SupportService.UpdateTicketRequest(
                null, null, "Title", "Text")));
        refused(() -> service.addEvidence(user.getId(), ticketId, TicketEvidence.Type.PHOTO, "a.png", new byte[] {1}));
        refused(() -> service.addStatement(user.getId(), ticketId, "My side"));
        refused(() -> service.updateStatement(user.getId(), ticketId, "My side, again"));
    }

    @Test
    @DisplayName("a suspended user cannot contest a decision")
    void cannotContest() {
        refused(() -> service.contest(user.getId(), UUID.randomUUID(), "I disagree"));
    }
}
