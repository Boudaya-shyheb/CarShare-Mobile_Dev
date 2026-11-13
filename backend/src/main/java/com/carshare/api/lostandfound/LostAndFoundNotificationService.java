package com.carshare.api.lostandfound;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The in-app notifications for Lost & Found. The server creates them as things happen (a likely
 * match, a confirmed match, a meeting, a return, a refusal); the two people involved read them
 * from the bell. No email: only rows in a table, read through the endpoints below.
 *
 * <p>Every trigger runs inside the caller's transaction, so a notification exists exactly when
 * the thing it announces was saved.
 */
@Service
public class LostAndFoundNotificationService {
    private static final List<LostAndFoundHandover.Status> LIVE =
            List.of(LostAndFoundHandover.Status.PROPOSED, LostAndFoundHandover.Status.ARRANGED);

    private final LostAndFoundNotificationRepository notifications;
    private final LostAndFoundReportRepository reports;
    private final LostAndFoundHandoverRepository handovers;

    public LostAndFoundNotificationService(LostAndFoundNotificationRepository notifications,
            LostAndFoundReportRepository reports, LostAndFoundHandoverRepository handovers) {
        this.notifications = notifications;
        this.reports = reports;
        this.handovers = handovers;
    }

    // --- triggers -----------------------------------------------------------------------------

    /**
     * A report was just created: if an open report of the opposite type on the same trip looks like
     * the same item (the phone's own rule), both reporters hear about it. Only the best candidate
     * counts, as on the phone.
     */
    public void matchFoundFor(LostAndFoundReport created) {
        LostAndFoundReport best = reports.findByTrip_IdOrderByCreatedAtDesc(created.getTrip().getId())
                .stream()
                .filter(other -> !other.getId().equals(created.getId()))
                .filter(other -> LostAndFoundMatcher.matches(created, other, true))
                .filter(this::isNotInALiveHandover)
                .max(Comparator.comparingInt(other -> LostAndFoundMatcher.score(created, other)))
                .orElse(null);
        if (best == null) return;

        String route = route(created);
        String item = created.getTitle().trim();
        notify(created.getReporter(), LostAndFoundNotification.Type.MATCH_FOUND, created.getId(), null,
                "Possible match found",
                created.getType() == LostAndFoundReport.Type.LOST
                        ? "A " + item.toLowerCase() + " was reported as found on " + route
                                + ". It may be yours: open it to check."
                        : "A " + item.toLowerCase() + " was reported as lost on " + route
                                + ". It may belong to its owner: open it to check.");
        notify(best.getReporter(), LostAndFoundNotification.Type.MATCH_FOUND, best.getId(), null,
                "Possible match found",
                best.getType() == LostAndFoundReport.Type.LOST
                        ? "A " + item.toLowerCase() + " was reported as found on " + route
                                + ". It may be yours: open it to check."
                        : "A " + item.toLowerCase() + " was reported as lost on " + route
                                + ". It may belong to its owner: open it to check.");
    }

    /** A handover was started: the other person is asked to carry on. */
    public void matchConfirmed(LostAndFoundHandover handover, UUID actorId) {
        AppUser actor = actorOf(handover, actorId);
        notifyOther(handover, actorId, LostAndFoundNotification.Type.MATCH_CONFIRMED, "Match confirmed",
                actor.getFullName() + " confirmed that your " + item(handover)
                        + " matches. Agree on a meeting place and time.");
    }

    public void meetingArranged(LostAndFoundHandover handover, UUID actorId) {
        notifyOther(handover, actorId, LostAndFoundNotification.Type.MEETING_ARRANGED, "Meeting arranged",
                "Meet at " + handover.getMeetingPoint() + ", " + handover.getMeetingTime() + ".");
    }

    /** The finder entered the right code: both people are told the item is back. */
    public void itemReturned(LostAndFoundHandover handover) {
        String body = "The " + item(handover) + " was handed back. This report is closed.";
        for (LostAndFoundReport report : List.of(handover.getLostReport(), handover.getFoundReport())) {
            notify(report.getReporter(), LostAndFoundNotification.Type.ITEM_RETURNED, report.getId(),
                    handover.getId(), "Item returned", body);
        }
    }

    public void handoverRejected(LostAndFoundHandover handover, UUID actorId) {
        AppUser actor = actorOf(handover, actorId);
        notifyOther(handover, actorId, LostAndFoundNotification.Type.NOT_MY_ITEM, "Match called off",
                actor.getFullName() + " said this is not the same item. Your report is open again.");
    }

    // --- reading ------------------------------------------------------------------------------

    @Transactional(readOnly = true)
    public List<NotificationView> mine(UUID userId) {
        return notifications.findByUser_IdOrderByCreatedAtDesc(userId).stream()
                .map(NotificationView::from).toList();
    }

    @Transactional(readOnly = true)
    public UnreadCount unreadCount(UUID userId) {
        return new UnreadCount(notifications.countByUser_IdAndReadAtIsNull(userId));
    }

    /** Marking one read is idempotent; somebody else's notification is simply not found. */
    @Transactional
    public NotificationView markRead(UUID userId, UUID notificationId) {
        LostAndFoundNotification notification = notifications.findByIdAndUser_Id(notificationId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "notification_not_found",
                        "Notification not found."));
        notification.markRead(Instant.now());
        return NotificationView.from(notification);
    }

    @Transactional
    public UnreadCount markAllRead(UUID userId) {
        notifications.markAllRead(userId, Instant.now());
        return new UnreadCount(0);
    }

    // --- helpers ------------------------------------------------------------------------------

    private boolean isNotInALiveHandover(LostAndFoundReport report) {
        return report.getType() == LostAndFoundReport.Type.LOST
                ? !handovers.existsByLostReport_IdAndStatusIn(report.getId(), LIVE)
                : !handovers.existsByFoundReport_IdAndStatusIn(report.getId(), LIVE);
    }

    /** Notifies whoever is on the other side of the handover from {@code actorId}. */
    private void notifyOther(LostAndFoundHandover handover, UUID actorId,
            LostAndFoundNotification.Type type, String title, String body) {
        boolean actorIsOwner = handover.getLostReport().getReporter().getId().equals(actorId);
        LostAndFoundReport recipientReport = actorIsOwner ? handover.getFoundReport() : handover.getLostReport();
        notify(recipientReport.getReporter(), type, recipientReport.getId(), handover.getId(), title, body);
    }

    private AppUser actorOf(LostAndFoundHandover handover, UUID actorId) {
        AppUser owner = handover.getLostReport().getReporter();
        return owner.getId().equals(actorId) ? owner : handover.getFoundReport().getReporter();
    }

    private static String item(LostAndFoundHandover handover) {
        return handover.getLostReport().getTitle().trim().toLowerCase();
    }

    /** "Ennasr → Sousse": the first part of each place label. */
    private static String route(LostAndFoundReport report) {
        return shortName(report.getTrip().getOriginLabel()) + " → "
                + shortName(report.getTrip().getDestinationLabel());
    }

    private static String shortName(String label) {
        if (label == null) return "?";
        int comma = label.indexOf(',');
        return (comma < 0 ? label : label.substring(0, comma)).trim();
    }

    private void notify(AppUser user, LostAndFoundNotification.Type type, UUID reportId, UUID handoverId,
            String title, String body) {
        notifications.save(new LostAndFoundNotification(user, type, reportId, handoverId, title, body));
    }

    public record NotificationView(UUID id, String type, UUID reportId, UUID handoverId, String title,
            String body, boolean read, Instant createdAt) {
        static NotificationView from(LostAndFoundNotification n) {
            return new NotificationView(n.getId(), n.getType().name(), n.getReportId(), n.getHandoverId(),
                    n.getTitle(), n.getBody(), n.getReadAt() != null, n.getCreatedAt());
        }
    }

    public record UnreadCount(long count) { }
}
