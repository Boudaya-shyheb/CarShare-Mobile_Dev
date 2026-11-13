package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.Trip;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpStatus;

/** What the server tells people, to whom, and when. */
class LostAndFoundNotificationServiceTest {
    private final LostAndFoundNotificationRepository notifications = mock(LostAndFoundNotificationRepository.class);
    private final LostAndFoundReportRepository reports = mock(LostAndFoundReportRepository.class);
    private final LostAndFoundHandoverRepository handovers = mock(LostAndFoundHandoverRepository.class);
    private LostAndFoundNotificationService service;
    private AppUser owner;
    private AppUser finder;
    private Trip trip;

    @BeforeEach
    void setUp() {
        service = new LostAndFoundNotificationService(notifications, reports, handovers);
        owner = new AppUser("Ines Trabelsi", "+21698765432", "ines@carshare.tn", "h", UserRole.PASSENGER);
        finder = new AppUser("Yacine Jomni", "+21612345678", "yacine@carshare.tn", "h", UserRole.DRIVER);
        trip = new Trip(finder, null, "Ennasr, Ariana, Tunis", 36.8, 10.15, "Sousse, Tunisie", 35.8, 10.6,
                Instant.now().plusSeconds(7200), 3, new BigDecimal("10.00"), false, null, null, null, null);
    }

    private LostAndFoundReport report(AppUser by, LostAndFoundReport.Type type, String title, String colour) {
        return new LostAndFoundReport(trip, by, type, title, "A thing" + (colour == null ? "" : "\n\nColor: " + colour));
    }

    private List<LostAndFoundNotification> saved(int expected) {
        ArgumentCaptor<LostAndFoundNotification> captor = ArgumentCaptor.forClass(LostAndFoundNotification.class);
        verify(notifications, org.mockito.Mockito.times(expected)).save(captor.capture());
        return captor.getAllValues();
    }

    // --- MATCH_FOUND ---------------------------------------------------------------------------

    @Test
    @DisplayName("a new report that matches an open one tells BOTH reporters, each about their own report")
    void matchFoundNotifiesBoth() {
        var lost = report(owner, LostAndFoundReport.Type.LOST, "Phone", "Black");
        var created = report(finder, LostAndFoundReport.Type.FOUND, "Phone", "Black");
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(created, lost));

        service.matchFoundFor(created);

        var rows = saved(2);
        assertEquals(LostAndFoundNotification.Type.MATCH_FOUND, rows.get(0).getType());
        assertEquals(finder, rows.get(0).getUser());
        assertEquals(created.getId(), rows.get(0).getReportId());
        assertEquals(owner, rows.get(1).getUser());
        assertEquals(lost.getId(), rows.get(1).getReportId());
        assertTrue(rows.get(1).getBody().contains("Ennasr → Sousse"), rows.get(1).getBody());
        assertTrue(rows.get(1).getBody().contains("may be yours"), rows.get(1).getBody());
    }

    @Test
    @DisplayName("no notification when nothing matches: other category, other colour, same person, 'Other'")
    void noMatchNoNotification() {
        var created = report(finder, LostAndFoundReport.Type.FOUND, "Phone", "Black");
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(
                created,
                report(owner, LostAndFoundReport.Type.LOST, "Keys", "Black"),
                report(owner, LostAndFoundReport.Type.LOST, "Phone", "Red"),
                report(finder, LostAndFoundReport.Type.LOST, "Phone", "Black"),
                report(owner, LostAndFoundReport.Type.FOUND, "Phone", "Black")));

        service.matchFoundFor(created);

        verify(notifications, never()).save(any());
    }

    @Test
    @DisplayName("'Other' reports never notify, whatever the other side reported")
    void otherNeverMatches() {
        var created = report(finder, LostAndFoundReport.Type.FOUND, "Other", null);
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId()))
                .thenReturn(List.of(created, report(owner, LostAndFoundReport.Type.LOST, "Other", null)));

        service.matchFoundFor(created);

        verify(notifications, never()).save(any());
    }

    @Test
    @DisplayName("a resolved report, or one already in a live handover, is not offered")
    void resolvedOrBusyCandidatesAreSkipped() {
        var created = report(finder, LostAndFoundReport.Type.FOUND, "Phone", null);
        var resolved = report(owner, LostAndFoundReport.Type.LOST, "Phone", null);
        resolved.resolve();
        var busy = report(owner, LostAndFoundReport.Type.LOST, "Phone", null);
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(created, resolved, busy));
        when(handovers.existsByLostReport_IdAndStatusIn(busy.getId(), List.of(
                LostAndFoundHandover.Status.PROPOSED, LostAndFoundHandover.Status.ARRANGED))).thenReturn(true);

        service.matchFoundFor(created);

        verify(notifications, never()).save(any());
    }

    @Test
    @DisplayName("with several candidates, the exact colour match is the one that counts")
    void bestCandidateWins() {
        var created = report(finder, LostAndFoundReport.Type.FOUND, "Bag", "Red");
        AppUser other = new AppUser("Sami", "+21655111222", "sami@carshare.tn", "h", UserRole.PASSENGER);
        var noColour = report(other, LostAndFoundReport.Type.LOST, "Bag", null);
        var exact = report(owner, LostAndFoundReport.Type.LOST, "Bag", "Red");
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(created, noColour, exact));

        service.matchFoundFor(created);

        var rows = saved(2);
        assertEquals(owner, rows.get(1).getUser(), "the red bag's owner, not the one with no colour");
    }

    // --- the handover steps --------------------------------------------------------------------

    private LostAndFoundHandover handover() {
        return new LostAndFoundHandover(trip,
                report(owner, LostAndFoundReport.Type.LOST, "Phone", null),
                report(finder, LostAndFoundReport.Type.FOUND, "Phone", null), owner);
    }

    @Test
    @DisplayName("MATCH_CONFIRMED goes to the other reporter, pointing at their own report")
    void matchConfirmedGoesToTheOtherPerson() {
        var handover = handover();

        service.matchConfirmed(handover, owner.getId());

        var row = saved(1).get(0);
        assertEquals(LostAndFoundNotification.Type.MATCH_CONFIRMED, row.getType());
        assertEquals(finder, row.getUser());
        assertEquals(handover.getFoundReport().getId(), row.getReportId());
        assertEquals(handover.getId(), row.getHandoverId());
        assertTrue(row.getBody().contains("Ines Trabelsi confirmed"), row.getBody());
    }

    @Test
    @DisplayName("MEETING_ARRANGED carries the place and the time to the other reporter")
    void meetingArrangedCarriesPlaceAndTime() {
        var handover = handover();
        handover.arrange("Ennasr metro station", "Today 18:00", "4321");

        service.meetingArranged(handover, finder.getId());

        var row = saved(1).get(0);
        assertEquals(LostAndFoundNotification.Type.MEETING_ARRANGED, row.getType());
        assertEquals(owner, row.getUser());
        assertEquals(handover.getLostReport().getId(), row.getReportId());
        assertTrue(row.getBody().contains("Ennasr metro station") && row.getBody().contains("Today 18:00"));
    }

    @Test
    @DisplayName("ITEM_RETURNED goes to both people, each about their own report")
    void itemReturnedGoesToBoth() {
        var handover = handover();

        service.itemReturned(handover);

        var rows = saved(2);
        assertEquals(List.of(owner, finder), rows.stream().map(LostAndFoundNotification::getUser).toList());
        assertTrue(rows.stream().allMatch(r -> r.getType() == LostAndFoundNotification.Type.ITEM_RETURNED));
        assertEquals(handover.getLostReport().getId(), rows.get(0).getReportId());
        assertEquals(handover.getFoundReport().getId(), rows.get(1).getReportId());
    }

    @Test
    @DisplayName("NOT_MY_ITEM goes to the other reporter only")
    void rejectionGoesToTheOtherPerson() {
        var handover = handover();

        service.handoverRejected(handover, finder.getId());

        var row = saved(1).get(0);
        assertEquals(LostAndFoundNotification.Type.NOT_MY_ITEM, row.getType());
        assertEquals(owner, row.getUser());
        assertTrue(row.getBody().contains("Yacine Jomni said this is not the same item"), row.getBody());
    }

    // --- reading and marking read --------------------------------------------------------------

    @Test
    @DisplayName("marking one read is idempotent, and somebody else's notification is not found")
    void markReadOnlyForTheOwner() {
        var note = new LostAndFoundNotification(owner, LostAndFoundNotification.Type.ITEM_RETURNED, null, null, "t", "b");
        when(notifications.findByIdAndUser_Id(note.getId(), owner.getId())).thenReturn(Optional.of(note));
        when(notifications.findByIdAndUser_Id(note.getId(), finder.getId())).thenReturn(Optional.empty());

        assertFalse(service.mine(owner.getId()).stream().anyMatch(v -> v.read()));
        assertTrue(service.markRead(owner.getId(), note.getId()).read());
        assertTrue(service.markRead(owner.getId(), note.getId()).read());
        ApiException error = assertThrows(ApiException.class, () -> service.markRead(finder.getId(), note.getId()));
        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("notification_not_found", error.getCode());
    }

    @Test
    @DisplayName("the unread count and read-all use the user's own rows")
    void unreadCountAndReadAll() {
        UUID id = owner.getId();
        when(notifications.countByUser_IdAndReadAtIsNull(id)).thenReturn(3L);

        assertEquals(3L, service.unreadCount(id).count());
        assertEquals(0L, service.markAllRead(id).count());
        verify(notifications).markAllRead(org.mockito.ArgumentMatchers.eq(id), any());
        assertNull(null);
    }
}
