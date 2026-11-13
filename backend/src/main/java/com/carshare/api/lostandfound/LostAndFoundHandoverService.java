package com.carshare.api.lostandfound;

import com.carshare.api.common.ApiException;
import com.carshare.api.lostandfound.LostAndFoundHandover.Status;
import com.carshare.api.users.ActiveUserGuard;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.nio.charset.StandardCharsets;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The handover of a lost item, shared by its two reporters.
 *
 * <p>The phones still decide <em>who matches whom</em>. What this service owns is everything that
 * happens after: the meeting point and time both sides read, the check code only the owner is
 * shown, and the finder's verification that closes both reports in one transaction.
 */
@Service
public class LostAndFoundHandoverService {

    static final Set<Status> ACTIVE = EnumSet.of(Status.PROPOSED, Status.ARRANGED);

    private static final int MAX_MEETING_POINT = 120;
    private static final int MAX_MEETING_TIME = 80;

    private final LostAndFoundHandoverRepository handovers;
    private final LostAndFoundReportRepository reports;
    private final UserRepository users;
    private final SecureRandom random = new SecureRandom();

    public LostAndFoundHandoverService(
            LostAndFoundHandoverRepository handovers,
            LostAndFoundReportRepository reports,
            UserRepository users) {
        this.handovers = handovers;
        this.reports = reports;
        this.users = users;
    }

    /**
     * Starts a handover for a pair the phone matched. Asking again for a pair that already has a
     * live handover returns that handover, so both phones can confirm the match independently.
     */
    @Transactional
    public HandoverView propose(UUID userId, UUID lostReportId, UUID foundReportId) {
        ActiveUserGuard.requireActive(users, userId);
        if (lostReportId == null || foundReportId == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "handover_reports_required",
                    "Choose the lost report and the found report to match.");
        }
        LostAndFoundReport lost = requireReport(lostReportId);
        LostAndFoundReport found = requireReport(foundReportId);

        if (lost.getType() != LostAndFoundReport.Type.LOST
                || found.getType() != LostAndFoundReport.Type.FOUND) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_report_pair",
                    "A handover needs one lost report and one found report.");
        }
        if (!lost.getTrip().getId().equals(found.getTrip().getId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_report_pair",
                    "Both reports must be about the same trip.");
        }
        UUID ownerId = lost.getReporter().getId();
        UUID finderId = found.getReporter().getId();
        if (ownerId.equals(finderId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_report_pair",
                    "The two reports must come from different people.");
        }
        if (!userId.equals(ownerId) && !userId.equals(finderId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_report_owner",
                    "Only the two people who made the reports can start a handover.");
        }

        var existing = handovers.findByLostReport_IdAndFoundReport_IdAndStatusIn(
                lostReportId, foundReportId, ACTIVE);
        if (existing.isPresent()) {
            return view(handovers.findDetailed(existing.get().getId()).orElseThrow(), userId);
        }

        requireOpen(lost);
        requireOpen(found);
        if (handovers.existsByLostReport_IdAndStatusIn(lostReportId, ACTIVE)
                || handovers.existsByFoundReport_IdAndStatusIn(foundReportId, ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "handover_already_active",
                    "One of these reports is already in another handover.");
        }

        AppUser creator = users.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                        "account_not_found", "Your account could not be found."));
        LostAndFoundHandover handover = handovers.save(
                new LostAndFoundHandover(lost.getTrip(), lost, found, creator));
        return view(handover, userId);
    }

    /** Either side sets or changes the meeting; the code is created on the first call. */
    @Transactional
    public HandoverView arrange(
            UUID userId, UUID handoverId, String meetingPoint, String meetingTime) {
        ActiveUserGuard.requireActive(users, userId);
        LostAndFoundHandover handover = requireParticipantHandover(userId, handoverId);
        requireActive(handover);

        String point = requireText(meetingPoint, MAX_MEETING_POINT, "Meeting point");
        String time = requireText(meetingTime, MAX_MEETING_TIME, "Date and time");
        handover.arrange(point, time, newCode());
        return view(handover, userId);
    }

    /** Every handover the user is one side of, each seen from the user's side. */
    @Transactional(readOnly = true)
    public List<HandoverView> mine(UUID userId) {
        return handovers.findAllForUser(userId).stream()
                .map(handover -> view(handover, userId))
                .toList();
    }

    /**
     * The finder types the code the owner read out. A right code closes the handover and both
     * reports together; a wrong one is counted, and after {@code MAX_FAILED_ATTEMPTS} the
     * handover stops accepting codes. The count must survive the error that reports it, hence
     * {@code noRollbackFor}.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public HandoverView verify(UUID userId, UUID handoverId, String code) {
        LostAndFoundHandover handover = requireParticipantHandover(userId, handoverId);
        if (!handover.getFoundReport().getReporter().getId().equals(userId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "only_finder_can_verify",
                    "Only the person who found the item can enter the code.");
        }
        switch (handover.getStatus()) {
            case COMPLETED -> throw new ApiException(HttpStatus.CONFLICT,
                    "handover_already_completed", "This item has already been returned.");
            case CANCELLED -> throw new ApiException(HttpStatus.CONFLICT, "handover_closed",
                    "This handover was cancelled.");
            case PROPOSED -> throw new ApiException(HttpStatus.CONFLICT,
                    "handover_not_arranged", "Arrange the meeting before entering the code.");
            default -> { }
        }
        if (code == null || !code.matches("\\d{4}")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_code",
                    "The code has exactly 4 digits.");
        }
        if (handover.isLocked()) {
            throw lockedError();
        }
        requireOpen(handover.getLostReport());
        requireOpen(handover.getFoundReport());

        boolean right = MessageDigest.isEqual(
                code.getBytes(StandardCharsets.UTF_8),
                handover.getCode().getBytes(StandardCharsets.UTF_8));
        if (!right) {
            handover.recordFailedAttempt();
            if (handover.isLocked()) {
                throw lockedError();
            }
            throw new ApiException(HttpStatus.BAD_REQUEST, "wrong_code",
                    "That code is not right. " + handover.attemptsLeft()
                            + (handover.attemptsLeft() == 1 ? " try left." : " tries left."));
        }

        handover.complete();
        handover.getLostReport().resolve();
        handover.getFoundReport().resolve();
        return view(handover, userId);
    }

    /** "Not my item": either side calls the handover off; both reports stay open. */
    @Transactional
    public HandoverView reject(UUID userId, UUID handoverId) {
        LostAndFoundHandover handover = requireParticipantHandover(userId, handoverId);
        requireActive(handover);
        handover.cancel();
        return view(handover, userId);
    }

    /** Called when an admin closes a report by hand: its live handovers can no longer finish. */
    @Transactional
    public void cancelActiveFor(UUID reportId) {
        handovers.findForReport(reportId, ACTIVE).forEach(LostAndFoundHandover::cancel);
    }

    // --- rules --------------------------------------------------------------------------------

    private LostAndFoundReport requireReport(UUID reportId) {
        return reports.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "report_not_found", "Report not found."));
    }

    private LostAndFoundHandover requireParticipantHandover(UUID userId, UUID handoverId) {
        LostAndFoundHandover handover = handovers.findDetailed(handoverId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "handover_not_found", "Handover not found."));
        boolean participant = userId.equals(handover.getLostReport().getReporter().getId())
                || userId.equals(handover.getFoundReport().getReporter().getId());
        if (!participant) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_handover_participant",
                    "Only the two people in this handover can use it.");
        }
        return handover;
    }

    private static void requireActive(LostAndFoundHandover handover) {
        if (!handover.getStatus().isActive()) {
            throw new ApiException(HttpStatus.CONFLICT, "handover_closed",
                    "This handover is already finished.");
        }
    }

    private static void requireOpen(LostAndFoundReport report) {
        if (report.getStatus() != LostAndFoundReport.Status.OPEN) {
            throw new ApiException(HttpStatus.CONFLICT, "report_not_open",
                    "One of the reports is already closed.");
        }
    }

    private static ApiException lockedError() {
        return new ApiException(HttpStatus.LOCKED, "handover_locked",
                "Too many wrong codes. Ask the owner to cancel and start again.");
    }

    private static String requireText(String value, int maxLength, String label) {
        String clean = value == null ? "" : value.strip();
        if (clean.isEmpty() || clean.length() > maxLength) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_handover_text",
                    label + " must contain between 1 and " + maxLength + " characters.");
        }
        return clean;
    }

    private String newCode() {
        return String.format("%04d", random.nextInt(10_000));
    }

    // --- views --------------------------------------------------------------------------------

    /**
     * One handover as {@code userId} sees it. The code is the owner's secret: the finder's copy of
     * this object never carries it, which is the whole point of checking it on the server.
     */
    static HandoverView view(LostAndFoundHandover handover, UUID userId) {
        AppUser owner = handover.getLostReport().getReporter();
        AppUser finder = handover.getFoundReport().getReporter();
        boolean isOwner = owner.getId().equals(userId);
        String code = isOwner && handover.getStatus() != Status.CANCELLED
                ? handover.getCode()
                : null;
        return new HandoverView(
                handover.getId(), handover.getTrip().getId(),
                handover.getLostReport().getId(), handover.getFoundReport().getId(),
                handover.getStatus(), handover.getMeetingPoint(), handover.getMeetingTime(),
                isOwner ? "OWNER" : "FINDER",
                (isOwner ? finder : owner).getFullName(),
                code, handover.attemptsLeft(), handover.getUpdatedAt());
    }

    public record HandoverView(
            UUID id, UUID tripId, UUID lostReportId, UUID foundReportId, Status status,
            String meetingPoint, String meetingTime, String role, String otherReporterName,
            String code, int attemptsLeft, Instant updatedAt) {
    }
}
