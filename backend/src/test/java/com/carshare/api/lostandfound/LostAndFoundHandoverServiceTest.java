package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.lostandfound.LostAndFoundHandover.Status;
import com.carshare.api.lostandfound.LostAndFoundHandoverService.HandoverView;
import com.carshare.api.reservation.Trip;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpStatus;

/**
 * The rules of the shared handover: who may start it, who sees the code, how the finder's
 * verification closes both reports, and what happens after wrong codes and after "Not my item".
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class LostAndFoundHandoverServiceTest {

    @Mock private LostAndFoundHandoverRepository handovers;
    @Mock private LostAndFoundReportRepository reports;
    @Mock private UserRepository users;

    private LostAndFoundHandoverService service;
    private AppUser owner;
    private AppUser finder;
    private AppUser stranger;
    private Trip trip;
    private LostAndFoundReport lost;
    private LostAndFoundReport found;

    @BeforeEach
    void setUp() {
        service = new LostAndFoundHandoverService(handovers, reports, users);
        owner = new AppUser("Ines Trabelsi", "+21698765432", "ines@carshare.tn", "h", UserRole.PASSENGER);
        finder = new AppUser("Yacine Jomni", "+21612345678", "yacine@carshare.tn", "h", UserRole.DRIVER);
        stranger = new AppUser("Sami Ben Ali", "+21655111222", "sami@carshare.tn", "h", UserRole.PASSENGER);
        trip = new Trip(finder, null, "Ennasr", 36.835, 10.155, "Sousse", 35.8256, 10.636,
                Instant.now().plus(2, ChronoUnit.HOURS), 3, new BigDecimal("10.00"), false, null,
                null, null, null);
        lost = new LostAndFoundReport(trip, owner, LostAndFoundReport.Type.LOST, "Phone",
                "Black phone\n\nColor: Black");
        found = new LostAndFoundReport(trip, finder, LostAndFoundReport.Type.FOUND, "Phone",
                "Black phone on the back seat\n\nColor: Black");
        when(reports.findById(lost.getId())).thenReturn(Optional.of(lost));
        when(reports.findById(found.getId())).thenReturn(Optional.of(found));
        when(users.findById(owner.getId())).thenReturn(Optional.of(owner));
        when(users.findById(finder.getId())).thenReturn(Optional.of(finder));
        when(handovers.save(any())).thenAnswer(call -> call.getArgument(0));
    }

    // --- starting a handover ------------------------------------------------------------------

    @Test
    @DisplayName("a matched pair starts a PROPOSED handover, seen from each side")
    void proposeStartsAHandover() {
        HandoverView mine = service.propose(owner.getId(), lost.getId(), found.getId());

        assertEquals(Status.PROPOSED, mine.status());
        assertEquals("OWNER", mine.role());
        assertEquals("Yacine Jomni", mine.otherReporterName());
        assertNull(mine.code(), "no code exists before the meeting is arranged");
        verify(handovers).save(any(LostAndFoundHandover.class));
    }

    @Test
    @DisplayName("the finder can start it too")
    void finderCanPropose() {
        HandoverView theirs = service.propose(finder.getId(), lost.getId(), found.getId());

        assertEquals("FINDER", theirs.role());
        assertEquals("Ines Trabelsi", theirs.otherReporterName());
    }

    @Test
    @DisplayName("two lost reports (or two found) are not a pair")
    void sameTypeIsRejected() {
        LostAndFoundReport anotherLost = new LostAndFoundReport(trip, finder,
                LostAndFoundReport.Type.LOST, "Keys", "Keys");
        when(reports.findById(anotherLost.getId())).thenReturn(Optional.of(anotherLost));

        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), lost.getId(), anotherLost.getId()));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_report_pair", error.getCode());
    }

    @Test
    @DisplayName("the lost id must be the LOST report, not the other way round")
    void swappedRolesAreRejected() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), found.getId(), lost.getId()));

        assertEquals("invalid_report_pair", error.getCode());
    }

    @Test
    @DisplayName("reports from two different trips are not a pair")
    void differentTripsAreRejected() {
        Trip other = new Trip(finder, null, "Tunis", 36.8, 10.18, "Sfax", 34.74, 10.76,
                Instant.now().plus(5, ChronoUnit.HOURS), 3, new BigDecimal("12.00"), false, null,
                null, null, null);
        LostAndFoundReport elsewhere = new LostAndFoundReport(other, finder,
                LostAndFoundReport.Type.FOUND, "Phone", "Phone");
        when(reports.findById(elsewhere.getId())).thenReturn(Optional.of(elsewhere));

        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), lost.getId(), elsewhere.getId()));

        assertEquals("invalid_report_pair", error.getCode());
    }

    @Test
    @DisplayName("a person cannot match their own two reports")
    void sameUserIsRejected() {
        LostAndFoundReport mineToo = new LostAndFoundReport(trip, owner,
                LostAndFoundReport.Type.FOUND, "Phone", "Phone");
        when(reports.findById(mineToo.getId())).thenReturn(Optional.of(mineToo));

        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), lost.getId(), mineToo.getId()));

        assertEquals("invalid_report_pair", error.getCode());
    }

    @Test
    @DisplayName("a report that is already resolved cannot start a handover")
    void closedReportIsRejected() {
        found.resolve();

        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), lost.getId(), found.getId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("report_not_open", error.getCode());
    }

    @Test
    @DisplayName("someone who made neither report gets 403")
    void strangerCannotPropose() {
        when(users.findById(stranger.getId())).thenReturn(Optional.of(stranger));
        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(stranger.getId(), lost.getId(), found.getId()));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("not_report_owner", error.getCode());
        verify(handovers, never()).save(any());
    }

    @Test
    @DisplayName("asking again for the same pair returns the live handover and creates nothing")
    void proposeIsIdempotent() {
        LostAndFoundHandover live = new LostAndFoundHandover(trip, lost, found, owner);
        when(handovers.findByLostReport_IdAndFoundReport_IdAndStatusIn(any(), any(), any()))
                .thenReturn(Optional.of(live));
        when(handovers.findDetailed(live.getId())).thenReturn(Optional.of(live));

        HandoverView again = service.propose(finder.getId(), lost.getId(), found.getId());

        assertEquals(live.getId(), again.id());
        verify(handovers, never()).save(any());
    }

    @Test
    @DisplayName("a report already in another live handover is refused")
    void onlyOneLiveHandoverPerReport() {
        when(handovers.existsByLostReport_IdAndStatusIn(any(), any())).thenReturn(true);

        ApiException error = assertThrows(ApiException.class,
                () -> service.propose(owner.getId(), lost.getId(), found.getId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("handover_already_active", error.getCode());
    }

    // --- arranging and who sees the code ------------------------------------------------------

    @Test
    @DisplayName("arranging creates a 4-digit code once, and either side may arrange")
    void arrangeCreatesTheCodeOnce() {
        LostAndFoundHandover handover = proposed();

        HandoverView first = service.arrange(finder.getId(), handover.getId(), " Ennasr metro ", "Today 18:00");
        String code = handover.getCode();
        HandoverView second = service.arrange(owner.getId(), handover.getId(), "Sousse bus station", "Today 19:00");

        assertEquals(Status.ARRANGED, first.status());
        assertNotNull(code);
        assertTrue(code.matches("\\d{4}"), "the code is exactly 4 digits: " + code);
        assertEquals("Ennasr metro", first.meetingPoint(), "the text is trimmed");
        assertEquals(code, handover.getCode(), "editing the meeting keeps the code");
        assertEquals("Sousse bus station", second.meetingPoint());
        assertEquals("Today 19:00", second.meetingTime());
    }

    @Test
    @DisplayName("only the LOST owner is shown the code; the finder's copy never has it")
    void onlyTheOwnerSeesTheCode() {
        LostAndFoundHandover handover = proposed();
        service.arrange(finder.getId(), handover.getId(), "Ennasr metro", "Today 18:00");
        when(handovers.findAllForUser(owner.getId())).thenReturn(List.of(handover));
        when(handovers.findAllForUser(finder.getId())).thenReturn(List.of(handover));

        HandoverView ownerSide = service.mine(owner.getId()).get(0);
        HandoverView finderSide = service.mine(finder.getId()).get(0);

        assertEquals(handover.getCode(), ownerSide.code());
        assertNull(finderSide.code());
        assertEquals(ownerSide.status(), finderSide.status(), "both sides share the status");
        assertEquals(ownerSide.meetingPoint(), finderSide.meetingPoint());
        assertEquals(ownerSide.meetingTime(), finderSide.meetingTime());
        assertEquals("OWNER", ownerSide.role());
        assertEquals("FINDER", finderSide.role());
    }

    @Test
    @DisplayName("an empty or over-long meeting point is a 400")
    void arrangeValidatesTheText() {
        LostAndFoundHandover handover = proposed();

        ApiException empty = assertThrows(ApiException.class,
                () -> service.arrange(owner.getId(), handover.getId(), "  ", "Today"));
        ApiException tooLong = assertThrows(ApiException.class,
                () -> service.arrange(owner.getId(), handover.getId(), "x".repeat(121), "Today"));

        assertEquals("invalid_handover_text", empty.getCode());
        assertEquals("invalid_handover_text", tooLong.getCode());
    }

    @Test
    @DisplayName("a non-participant gets 403 on arrange, verify and reject")
    void strangerIsForbiddenEverywhere() {
        LostAndFoundHandover handover = arranged();
        when(users.findById(stranger.getId())).thenReturn(Optional.of(stranger));

        for (Runnable call : List.<Runnable>of(
                () -> service.arrange(stranger.getId(), handover.getId(), "Here", "Now"),
                () -> service.verify(stranger.getId(), handover.getId(), "1234"),
                () -> service.reject(stranger.getId(), handover.getId()))) {
            ApiException error = assertThrows(ApiException.class, call::run);
            assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
            assertEquals("not_handover_participant", error.getCode());
        }
        assertEquals(Status.ARRANGED, handover.getStatus());
    }

    // --- verifying the code -------------------------------------------------------------------

    @Test
    @DisplayName("the right code completes the handover and resolves BOTH reports")
    void rightCodeClosesEverything() {
        LostAndFoundHandover handover = arranged();

        HandoverView done = service.verify(finder.getId(), handover.getId(), handover.getCode());

        assertEquals(Status.COMPLETED, done.status());
        assertEquals(LostAndFoundReport.Status.RESOLVED, lost.getStatus());
        assertEquals(LostAndFoundReport.Status.RESOLVED, found.getStatus());
        assertNull(done.code(), "the finder still never gets the code back");
    }

    @Test
    @DisplayName("the owner cannot verify their own code")
    void ownerCannotVerify() {
        LostAndFoundHandover handover = arranged();

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(owner.getId(), handover.getId(), handover.getCode()));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("only_finder_can_verify", error.getCode());
        assertEquals(Status.ARRANGED, handover.getStatus());
    }

    @Test
    @DisplayName("a wrong code is a 400, is counted, and nothing is closed")
    void wrongCodeIsCounted() {
        LostAndFoundHandover handover = arranged();
        String wrong = otherThan(handover.getCode());

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), wrong));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("wrong_code", error.getCode());
        assertEquals(1, handover.getFailedAttempts());
        assertEquals(Status.ARRANGED, handover.getStatus());
        assertEquals(LostAndFoundReport.Status.OPEN, lost.getStatus());
        assertEquals(LostAndFoundReport.Status.OPEN, found.getStatus());
    }

    @Test
    @DisplayName("five wrong codes lock it, and then even the right code is refused")
    void fiveWrongCodesLock() {
        LostAndFoundHandover handover = arranged();
        String wrong = otherThan(handover.getCode());
        for (int i = 1; i < LostAndFoundHandover.MAX_FAILED_ATTEMPTS; i++) {
            ApiException error = assertThrows(ApiException.class,
                    () -> service.verify(finder.getId(), handover.getId(), wrong));
            assertEquals("wrong_code", error.getCode());
        }

        ApiException fifth = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), wrong));
        ApiException afterLock = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), handover.getCode()));

        assertEquals(HttpStatus.LOCKED, fifth.getStatus());
        assertEquals("handover_locked", fifth.getCode());
        assertEquals("handover_locked", afterLock.getCode());
        assertEquals(5, handover.getFailedAttempts());
        assertEquals(Status.ARRANGED, handover.getStatus());
        assertEquals(LostAndFoundReport.Status.OPEN, lost.getStatus());
    }

    @Test
    @DisplayName("something that is not 4 digits is a 400 and does not use up a try")
    void malformedCodeIsNotCounted() {
        LostAndFoundHandover handover = arranged();

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), "12a4"));

        assertEquals("invalid_code", error.getCode());
        assertEquals(0, handover.getFailedAttempts());
    }

    @Test
    @DisplayName("verifying before the meeting is arranged is a 409")
    void notArrangedYet() {
        LostAndFoundHandover handover = proposed();

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), "1234"));

        assertEquals("handover_not_arranged", error.getCode());
    }

    @Test
    @DisplayName("verifying twice: the second time is a 409, not a second resolve")
    void doubleVerifyIsRefused() {
        LostAndFoundHandover handover = arranged();
        service.verify(finder.getId(), handover.getId(), handover.getCode());

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), handover.getCode()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("handover_already_completed", error.getCode());
    }

    @Test
    @DisplayName("if a report was closed meanwhile (an admin), verifying is a 409")
    void reportAlreadyResolved() {
        LostAndFoundHandover handover = arranged();
        lost.resolve();

        ApiException error = assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), handover.getId(), handover.getCode()));

        assertEquals("report_not_open", error.getCode());
        assertEquals(Status.ARRANGED, handover.getStatus());
    }

    // --- "Not my item" ------------------------------------------------------------------------

    @Test
    @DisplayName("either side can call it off; both reports stay open")
    void rejectCancelsAndKeepsReportsOpen() {
        for (AppUser who : List.of(owner, finder)) {
            LostAndFoundHandover handover = arranged();

            HandoverView view = service.reject(who.getId(), handover.getId());

            assertEquals(Status.CANCELLED, view.status());
            assertNull(view.code(), "a cancelled handover shows no code to the owner");
            assertEquals(LostAndFoundReport.Status.OPEN, lost.getStatus());
            assertEquals(LostAndFoundReport.Status.OPEN, found.getStatus());
        }
    }

    @Test
    @DisplayName("a cancelled or completed handover cannot be rejected, arranged or verified again")
    void closedHandoversStayClosed() {
        LostAndFoundHandover cancelled = arranged();
        service.reject(owner.getId(), cancelled.getId());
        LostAndFoundHandover completed = arranged();
        service.verify(finder.getId(), completed.getId(), completed.getCode());

        for (LostAndFoundHandover handover : List.of(cancelled, completed)) {
            assertEquals("handover_closed", assertThrows(ApiException.class,
                    () -> service.reject(owner.getId(), handover.getId())).getCode());
            assertEquals("handover_closed", assertThrows(ApiException.class,
                    () -> service.arrange(owner.getId(), handover.getId(), "Here", "Now")).getCode());
        }
        assertEquals("handover_closed", assertThrows(ApiException.class,
                () -> service.verify(finder.getId(), cancelled.getId(), "1234")).getCode());
    }

    @Test
    @DisplayName("an admin closing a report calls off its live handovers")
    void adminClosureCancelsLiveHandovers() {
        LostAndFoundHandover handover = arranged();
        when(handovers.findForReport(any(), any())).thenReturn(List.of(handover));

        service.cancelActiveFor(lost.getId());

        assertEquals(Status.CANCELLED, handover.getStatus());
    }

    // --- helpers ------------------------------------------------------------------------------

    private LostAndFoundHandover proposed() {
        LostAndFoundHandover handover = new LostAndFoundHandover(trip, lost, found, owner);
        when(handovers.findDetailed(handover.getId())).thenReturn(Optional.of(handover));
        return handover;
    }

    private LostAndFoundHandover arranged() {
        LostAndFoundHandover handover = proposed();
        service.arrange(owner.getId(), handover.getId(), "Ennasr metro", "Today 18:00");
        return handover;
    }

    private static String otherThan(String code) {
        return code.equals("0000") ? "0001" : "0000";
    }
}
