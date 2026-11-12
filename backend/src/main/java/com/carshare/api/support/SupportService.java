package com.carshare.api.support;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.Reservation;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.ReservationStatus;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.reservation.TripStatus;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SupportService {
    private static final Set<ReservationStatus> SUPPORT_PARTICIPANT_STATUSES =
            Set.of(ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED,
                    ReservationStatus.NO_SHOW, ReservationStatus.CANCELLED);
    private static final Set<SupportTicket.Status> ACTIVE_TICKET_STATUSES =
            Set.of(SupportTicket.Status.OPEN, SupportTicket.Status.AWAITING_RESPONSE,
                    SupportTicket.Status.UNDER_REVIEW, SupportTicket.Status.CONTESTED);

    private final SupportTicketRepository tickets;
    private final UserRepository users;
    private final TripRepository trips;
    private final ReservationRepository reservations;
    private final TicketCategoryRepository categories;
    private final TicketStatusHistoryRepository history;
    private final TicketEvidenceRepository evidence;
    private final TicketStatementRepository statements;
    private final TicketDecisionRepository decisions;
    private final TicketContestationRepository contestations;
    private final SupportNotificationRepository notifications;
    private final SupportEvidenceStorage evidenceStorage;
    private final TicketPriorityService priority;

    public SupportService(SupportTicketRepository tickets, UserRepository users,
            TripRepository trips, ReservationRepository reservations,
            TicketCategoryRepository categories, TicketStatusHistoryRepository history,
            TicketEvidenceRepository evidence, TicketStatementRepository statements,
            TicketDecisionRepository decisions, TicketContestationRepository contestations,
            SupportNotificationRepository notifications,
            SupportEvidenceStorage evidenceStorage, TicketPriorityService priority) {
        this.tickets = tickets;
        this.users = users;
        this.trips = trips;
        this.reservations = reservations;
        this.categories = categories;
        this.history = history;
        this.evidence = evidence;
        this.statements = statements;
        this.decisions = decisions;
        this.contestations = contestations;
        this.notifications = notifications;
        this.evidenceStorage = evidenceStorage;
        this.priority = priority;
    }

    @Transactional(readOnly = true)
    public List<CategoryView> activeCategories() {
        return categories.findByActiveTrueOrderByNameAsc().stream().map(CategoryView::from).toList();
    }

    @Transactional(readOnly = true)
    public List<CategoryView> allCategories() {
        return categories.findAllByOrderByNameAsc().stream().map(CategoryView::from).toList();
    }

    @Transactional
    public CategoryView createCategory(CategoryRequest request) {
        String name = clean(request.name(), 60, "Category name");
        validateCategory(request);
        if (categories.existsByNameIgnoreCase(name)) {
            throw new ApiException(HttpStatus.CONFLICT, "category_exists",
                    "A support category with this name already exists.");
        }
        TicketCategory category = new TicketCategory(name, request.severity(), request.priority(),
                request.responseDelayHours(), request.verificationType());
        return CategoryView.from(categories.save(category));
    }

    @Transactional
    public CategoryView updateCategory(UUID categoryId, CategoryRequest request) {
        TicketCategory category = category(categoryId);
        String name = clean(request.name(), 60, "Category name");
        validateCategory(request);
        categories.findByNameIgnoreCase(name).filter(found -> !found.getId().equals(categoryId))
                .ifPresent(found -> {
                    throw new ApiException(HttpStatus.CONFLICT, "category_exists",
                            "A support category with this name already exists.");
                });
        category.update(name, request.severity(), request.priority(),
                request.responseDelayHours(), request.verificationType());
        if (request.active()) category.activate(); else category.deactivate();
        return CategoryView.from(category);
    }

    @Transactional
    public void deleteOrDeactivateCategory(UUID categoryId) {
        TicketCategory category = category(categoryId);
        if (tickets.countByCategoryDefinition_Id(categoryId) == 0) {
            categories.delete(category);
        } else {
            category.deactivate();
        }
    }

    @Transactional(readOnly = true)
    public List<TicketView> myTickets(UUID userId) {
        return tickets.findVisibleToUser(userId, SUPPORT_PARTICIPANT_STATUSES).stream()
                .map(this::ticketView).toList();
    }

    @Transactional(readOnly = true)
    public List<ReportTargetView> reportTargets(UUID userId, UUID tripId) {
        Trip trip = trips.findById(tripId)
                .orElseThrow(() -> notFound("trip_not_found", "The selected trip was not found."));
        if (trip.isDrivenBy(userId)) {
            return reservations.findByTrip_IdAndStatusIn(
                            tripId, SUPPORT_PARTICIPANT_STATUSES).stream()
                    .map(reservation -> new ReportTargetView(
                            reservation.getPassenger().getId(),
                            reservation.getPassenger().getFullName(),
                            reservation.getId(), "PASSENGER"))
                    .toList();
        }
        return reservations.findByTrip_IdAndPassenger_IdAndStatusIn(
                        tripId, userId, SUPPORT_PARTICIPANT_STATUSES)
                .map(reservation -> List.of(new ReportTargetView(
                        trip.getDriver().getId(), trip.getDriver().getFullName(),
                        reservation.getId(), "DRIVER")))
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN,
                        "not_trip_participant",
                        "Only participants can report an issue about this trip."));
    }

    @Transactional(readOnly = true)
    public List<NotificationView> notifications(UUID userId) {
        return notifications.findByUser_IdOrderByCreatedAtDesc(userId).stream()
                .map(NotificationView::from).toList();
    }

    @Transactional(readOnly = true)
    public UnreadCount unreadCount(UUID userId) {
        return new UnreadCount(notifications.countByUser_IdAndReadAtIsNull(userId));
    }

    @Transactional
    public NotificationView markNotificationRead(UUID userId, UUID notificationId) {
        SupportNotification notification = notifications.findByIdAndUser_Id(
                        notificationId, userId)
                .orElseThrow(() -> notFound(
                        "notification_not_found", "Support notification not found."));
        notification.markRead();
        return NotificationView.from(notification);
    }

    @Transactional(readOnly = true)
    public TicketView myTicket(UUID userId, UUID ticketId) {
        return ticketView(participantTicket(userId, ticketId));
    }

    @Transactional(readOnly = true)
    public List<TicketView> allTickets() {
        Comparator<SupportTicket> adminPriorityOrder = Comparator
                .comparingInt((SupportTicket ticket) ->
                        ACTIVE_TICKET_STATUSES.contains(ticket.getStatus()) ? 0 : 1)
                .thenComparing(SupportTicket::getPriorityScore, Comparator.reverseOrder())
                .thenComparing(SupportTicket::getDeadline,
                        Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(SupportTicket::getCreatedAt,
                        Comparator.nullsLast(Comparator.reverseOrder()));
        return tickets.findAllByOrderByCreatedAtDesc().stream()
                .sorted(adminPriorityOrder).map(this::ticketView).toList();
    }

    @Transactional(readOnly = true)
    public AdminTicketDetailsView adminTicketDetails(UUID ticketId) {
        SupportTicket ticket = tickets.findDetailedById(ticketId)
                .orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
        return new AdminTicketDetailsView(
                ticketView(ticket),
                evidence.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                        .map(EvidenceView::from).toList(),
                statements.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                        .map(StatementView::from).toList(),
                decisions.findByTicket_IdOrderByDecisionNumberAsc(ticketId).stream()
                        .map(DecisionView::from).toList(),
                history.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                        .map(HistoryView::from).toList(),
                contestationViews(ticketId));
    }

    @Transactional(readOnly = true)
    public EvidenceContent adminEvidenceContent(UUID ticketId, UUID evidenceId) {
        if (!tickets.existsById(ticketId)) {
            throw notFound("ticket_not_found", "Support ticket not found.");
        }
        TicketEvidence item = evidence.findByIdAndTicket_Id(evidenceId, ticketId)
                .orElseThrow(() -> notFound("evidence_not_found", "Evidence not found."));
        return new EvidenceContent(item.getOriginalFileName(), item.getContentType(),
                evidenceStorage.read(item.getFilePath()));
    }

    @Transactional
    public TicketView create(UUID userId, TicketRequest request) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        TicketCategory category = resolveCategory(request.categoryId(), request.category());
        String title = clean(request.title(), 120, "Title");
        String description = clean(request.description(), 1500, "Description");

        UUID tripId = request.tripId();
        AppUser reportedUser = null;
        if (request.reservationId() != null) {
            Reservation reservation = reservations.findById(request.reservationId())
                    .orElseThrow(() -> notFound("reservation_not_found",
                            "The selected reservation was not found."));
            Trip trip = reservation.getTrip();
            boolean isPassenger = reservation.isHeldBy(userId);
            boolean isDriver = trip.isDrivenBy(userId);
            if (!isPassenger && !isDriver) {
                throw new ApiException(HttpStatus.FORBIDDEN, "not_trip_participant",
                        "Only participants can report an issue about this trip.");
            }
            boolean finalTrip = trip.getStatus() == TripStatus.COMPLETED
                    || trip.getStatus() == TripStatus.CANCELLED
                    || reservation.getStatus() == ReservationStatus.NO_SHOW;
            if (!finalTrip) {
                throw new ApiException(HttpStatus.CONFLICT, "trip_not_finished",
                        "A support ticket can be opened after the trip has ended.");
            }
            Instant finishedAt = trip.getUpdatedAt() == null
                    ? trip.expectedArrival() : trip.getUpdatedAt();
            if (finishedAt.isBefore(Instant.now().minus(7, ChronoUnit.DAYS))) {
                throw new ApiException(HttpStatus.CONFLICT, "ticket_window_expired",
                        "A trip issue must be reported within seven days.");
            }
            if (tickets.existsByReservationIdAndCategoryDefinition_Id(
                    request.reservationId(), category.getId())) {
                throw new ApiException(HttpStatus.CONFLICT, "ticket_already_exists",
                        "A ticket already exists for this reservation and category.");
            }
            tripId = trip.getId();
            reportedUser = isPassenger ? trip.getDriver() : reservation.getPassenger();
        } else if (tripId != null) {
            verifyLegacyTripParticipant(userId, tripId);
        }

        SupportTicket ticket = tickets.save(new SupportTicket(user, tripId,
                request.reservationId(), reportedUser, category, title, description));
        history.save(new TicketStatusHistory(ticket, null, SupportTicket.Status.OPEN,
                user, false, "Ticket created"));
        notifyUser(user, ticket, "TICKET_CREATED", "Support ticket created",
                ticket.getReference() + " was submitted successfully.");
        if (reportedUser != null) {
            ticket.awaitResponse();
            history.save(new TicketStatusHistory(ticket, SupportTicket.Status.OPEN,
                    SupportTicket.Status.AWAITING_RESPONSE, user, true,
                    "Response requested from the reported user"));
            notifyUser(reportedUser, ticket, "RESPONSE_REQUESTED",
                    "Your response is requested",
                    "You are involved in " + ticket.getReference()
                            + ". Add your statement and evidence before review.");
        }
        priority.refresh(ticket);
        return ticketView(ticket);
    }

    @Transactional
    public TicketView update(UUID userId, UUID ticketId, UpdateTicketRequest request) {
        SupportTicket ticket = ownedTicket(userId, ticketId);
        TicketCategory category = resolveCategory(request.categoryId(), request.category());
        try {
            ticket.updateOpen(category, clean(request.title(), 120, "Title"),
                    clean(request.description(), 1500, "Description"));
        } catch (IllegalStateException error) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_not_editable", error.getMessage());
        }
        priority.refresh(ticket);
        return ticketView(ticket);
    }

    @Transactional
    public TicketView withdraw(UUID userId, UUID ticketId) {
        SupportTicket ticket = ownedTicket(userId, ticketId);
        try {
            ticket.withdraw();
        } catch (IllegalStateException error) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_not_withdrawable", error.getMessage());
        }
        AppUser actor = ticket.getUser();
        history.save(new TicketStatusHistory(ticket, SupportTicket.Status.OPEN,
                SupportTicket.Status.WITHDRAWN, actor, false, "Withdrawn by its author"));
        return ticketView(ticket);
    }

    @Transactional(readOnly = true)
    public List<EvidenceView> evidence(UUID userId, UUID ticketId) {
        participantTicket(userId, ticketId);
        return evidence.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                .map(EvidenceView::from).toList();
    }

    @Transactional
    public EvidenceView addEvidence(UUID userId, UUID ticketId, TicketEvidence.Type type,
            String originalFileName, byte[] bytes) {
        SupportTicket ticket = participantTicket(userId, ticketId);
        requireBeforeReview(ticket, "Evidence can only be added before review starts.");
        if (type == null || type == TicketEvidence.Type.TRIP_DATA) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_evidence_type",
                    "Users can add photo or document evidence.");
        }
        AppUser uploader = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        SupportEvidenceStorage.StoredEvidence stored = evidenceStorage.save(bytes);
        boolean photo = stored.mimeType().startsWith("image/");
        if ((type == TicketEvidence.Type.PHOTO && !photo)
                || (type == TicketEvidence.Type.DOCUMENT && photo)) {
            evidenceStorage.delete(stored.fileName());
            throw new ApiException(HttpStatus.BAD_REQUEST, "evidence_type_mismatch",
                    "The selected evidence type does not match the file content.");
        }
        try {
            TicketEvidence item = evidence.save(new TicketEvidence(ticket, type,
                    stored.fileName(), safeFileName(originalFileName), stored.mimeType(),
                    bytes.length, uploader));
            notifyOtherParty(ticket, userId, "EVIDENCE_ADDED", "New ticket evidence",
                    uploader.getFullName() + " added evidence to " + ticket.getReference() + ".");
            return EvidenceView.from(item);
        } catch (RuntimeException exception) {
            evidenceStorage.delete(stored.fileName());
            throw exception;
        }
    }

    @Transactional(readOnly = true)
    public EvidenceContent evidenceContent(UUID userId, UUID ticketId, UUID evidenceId) {
        participantTicket(userId, ticketId);
        TicketEvidence item = evidence.findByIdAndTicket_Id(evidenceId, ticketId)
                .orElseThrow(() -> notFound("evidence_not_found", "Evidence not found."));
        return new EvidenceContent(item.getOriginalFileName(), item.getContentType(),
                evidenceStorage.read(item.getFilePath()));
    }

    @Transactional
    public void deleteEvidence(UUID userId, UUID ticketId, UUID evidenceId) {
        SupportTicket ticket = participantTicket(userId, ticketId);
        requireBeforeReview(ticket, "Evidence can only be removed before review starts.");
        TicketEvidence item = evidence.findByIdAndTicket_Id(evidenceId, ticketId)
                .orElseThrow(() -> notFound("evidence_not_found", "Evidence not found."));
        if (item.getUploadedBy() == null || !item.getUploadedBy().getId().equals(userId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "evidence_not_owned",
                    "You can only remove evidence that you uploaded.");
        }
        evidenceStorage.delete(item.getFilePath());
        evidence.delete(item);
    }

    @Transactional(readOnly = true)
    public List<StatementView> statements(UUID userId, UUID ticketId) {
        participantTicket(userId, ticketId);
        return statements.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                .map(StatementView::from).toList();
    }

    @Transactional
    public StatementView addStatement(UUID userId, UUID ticketId, String text) {
        SupportTicket ticket = participantTicket(userId, ticketId);
        requireBeforeReview(ticket, "A statement can only be added before review starts.");
        if (statements.findByTicket_IdAndAuthor_Id(ticketId, userId).isPresent()) {
            throw new ApiException(HttpStatus.CONFLICT, "statement_exists",
                    "You already added a statement to this ticket.");
        }
        AppUser author = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        TicketStatement statement = statements.save(
                new TicketStatement(ticket, author, clean(text, 2000, "Statement")));
        notifyOtherParty(ticket, userId, "STATEMENT_ADDED", "New ticket statement",
                author.getFullName() + " responded to " + ticket.getReference() + ".");
        return StatementView.from(statement);
    }

    @Transactional
    public StatementView updateStatement(UUID userId, UUID ticketId, String text) {
        SupportTicket ticket = participantTicket(userId, ticketId);
        requireBeforeReview(ticket, "A statement can only be edited before review starts.");
        TicketStatement statement = statements.findByTicket_IdAndAuthor_Id(ticketId, userId)
                .orElseThrow(() -> notFound("statement_not_found", "Statement not found."));
        statement.edit(clean(text, 2000, "Statement"));
        notifyOtherParty(ticket, userId, "STATEMENT_UPDATED", "Ticket statement updated",
                "A statement was updated in " + ticket.getReference() + ".");
        return StatementView.from(statement);
    }

    @Transactional(readOnly = true)
    public List<DecisionView> decisions(UUID userId, UUID ticketId) {
        participantTicket(userId, ticketId);
        return decisions.findByTicket_IdOrderByDecisionNumberAsc(ticketId).stream()
                .map(DecisionView::from).toList();
    }

    @Transactional(readOnly = true)
    public List<HistoryView> history(UUID userId, UUID ticketId) {
        participantTicket(userId, ticketId);
        return history.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                .map(HistoryView::from).toList();
    }

    @Transactional(readOnly = true)
    public List<ContestationView> contestations(UUID userId, UUID ticketId) {
        participantTicket(userId, ticketId);
        return contestationViews(ticketId);
    }

    @Transactional(readOnly = true)
    public List<ContestationView> contestationsForAdmin(UUID ticketId) {
        if (!tickets.existsById(ticketId)) {
            throw notFound("ticket_not_found", "Support ticket not found.");
        }
        return contestationViews(ticketId);
    }

    @Transactional
    public ContestationView contest(UUID userId, UUID ticketId, String reason) {
        SupportTicket ticket = participantTicket(userId, ticketId);
        if (ticket.getStatus() != SupportTicket.Status.RESOLVED) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_not_resolved",
                    "Only a resolved ticket can be contested.");
        }
        List<TicketDecision> ticketDecisions =
                decisions.findByTicket_IdOrderByDecisionNumberAsc(ticketId);
        if (ticketDecisions.isEmpty()) {
            throw new ApiException(HttpStatus.CONFLICT, "decision_not_found",
                    "This ticket has no decision to contest.");
        }
        TicketDecision latest = ticketDecisions.get(ticketDecisions.size() - 1);
        if (latest.isFinalDecision()) {
            throw new ApiException(HttpStatus.CONFLICT, "decision_is_final",
                    "The final decision cannot be contested.");
        }
        if (latest.getDecidedAt().plus(72, ChronoUnit.HOURS).isBefore(Instant.now())) {
            throw new ApiException(HttpStatus.CONFLICT, "contestation_window_expired",
                    "A decision must be contested within 72 hours.");
        }
        if (contestations.existsByTicket_IdAndContestedBy_Id(ticketId, userId)) {
            throw new ApiException(HttpStatus.CONFLICT, "contestation_exists",
                    "You have already contested this ticket.");
        }
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        TicketContestation contestation = contestations.save(new TicketContestation(ticket, user,
                clean(reason, 1000, "Contestation reason")));
        SupportTicket.Status previous = ticket.getStatus();
        ticket.contest();
        history.save(new TicketStatusHistory(ticket, previous, SupportTicket.Status.CONTESTED,
                user, false, "Decision contested"));
        notifyOtherParty(ticket, userId, "TICKET_CONTESTED", "Decision contested",
                ticket.getReference() + " has been contested.");
        return ContestationView.from(contestation);
    }

    @Transactional
    public TicketView changeStatus(UUID agentId, UUID ticketId, SupportTicket.Status next,
            String reason) {
        AppUser agent = users.findById(agentId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        SupportTicket ticket = tickets.findDetailedById(ticketId)
                .orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
        if (next == null || next == SupportTicket.Status.RESOLVED
                || next == SupportTicket.Status.WITHDRAWN
                || next == SupportTicket.Status.CONTESTED) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_ticket_status",
                    "Use the decision or contestation endpoint for this status.");
        }
        SupportTicket.Status previous = ticket.getStatus();
        try {
            ticket.moveTo(next);
        } catch (IllegalStateException error) {
            throw new ApiException(HttpStatus.CONFLICT, "invalid_ticket_transition",
                    error.getMessage());
        }
        history.save(new TicketStatusHistory(ticket, previous, next, agent, false,
                clean(reason, 500, "Status reason")));
        notifyTicketParties(ticket, "STATUS_CHANGED", "Ticket status updated",
                ticket.getReference() + " is now " + next.name().replace('_', ' ') + ".");
        return ticketView(ticket);
    }

    @Transactional
    public DecisionView decide(UUID agentId, UUID ticketId, DecisionRequest request) {
        AppUser agent = users.findById(agentId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        SupportTicket ticket = tickets.findDetailedById(ticketId)
                .orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
        if (ticket.getStatus() == SupportTicket.Status.WITHDRAWN
                || ticket.getStatus() == SupportTicket.Status.CLOSED) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_not_decidable",
                    "A withdrawn or closed ticket cannot receive a decision.");
        }
        List<TicketDecision> existing = decisions.findByTicket_IdOrderByDecisionNumberAsc(ticketId);
        int number = existing.size() + 1;
        if (number > 2) {
            throw new ApiException(HttpStatus.CONFLICT, "decision_is_final",
                    "The final decision has already been recorded.");
        }
        if (request.result() == null || request.penaltyPoints() < 0
                || request.penaltyPoints() > 12) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_decision",
                    "Choose a result and penalty points between 0 and 12.");
        }
        if (number == 2 && ticket.getStatus() != SupportTicket.Status.CONTESTED
                && ticket.getStatus() != SupportTicket.Status.UNDER_REVIEW) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_not_contested",
                    "A second decision requires a contested ticket under review.");
        }
        if (request.result() == TicketDecision.Result.REJECTED && request.penaltyPoints() != 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_penalty_points",
                    "A rejected complaint cannot apply penalty points.");
        }
        TicketDecision decision = decisions.save(new TicketDecision(ticket, request.result(),
                clean(request.reason(), 1500, "Decision reason"), request.penaltyPoints(),
                agent, false, number, number == 2));
        SupportTicket.Status previous = ticket.getStatus();
        ticket.resolve(request.reason().strip());
        history.save(new TicketStatusHistory(ticket, previous, SupportTicket.Status.RESOLVED,
                agent, false, "Support decision recorded"));
        notifyTicketParties(ticket, "DECISION_RECORDED", "Support decision available",
                "A decision was recorded for " + ticket.getReference() + ".");
        return DecisionView.from(decision);
    }

    private void notifyOtherParty(SupportTicket ticket, UUID actorId, String type,
            String title, String message) {
        AppUser opener = ticket.getUser();
        if (opener != null && !opener.getId().equals(actorId)) {
            notifyUser(opener, ticket, type, title, message);
            return;
        }
        AppUser reported = ticket.getReportedUser();
        if (reported != null && !reported.getId().equals(actorId)) {
            notifyUser(reported, ticket, type, title, message);
            return;
        }
        if (ticket.getReservationId() != null) {
            reservations.findById(ticket.getReservationId()).ifPresent(reservation -> {
                AppUser other = reservation.isHeldBy(actorId)
                        ? reservation.getTrip().getDriver() : reservation.getPassenger();
                if (!other.getId().equals(actorId)) {
                    notifyUser(other, ticket, type, title, message);
                }
            });
        }
    }

    private void notifyTicketParties(SupportTicket ticket, String type,
            String title, String message) {
        Set<UUID> notified = new HashSet<>();
        notifyOnce(ticket.getUser(), ticket, type, title, message, notified);
        notifyOnce(ticket.getReportedUser(), ticket, type, title, message, notified);
        if (ticket.getReservationId() != null && ticket.getReportedUser() == null) {
            reservations.findById(ticket.getReservationId()).ifPresent(reservation -> {
                notifyOnce(reservation.getPassenger(), ticket, type, title, message, notified);
                notifyOnce(reservation.getTrip().getDriver(), ticket,
                        type, title, message, notified);
            });
        }
    }

    private void notifyOnce(AppUser user, SupportTicket ticket, String type,
            String title, String message, Set<UUID> notified) {
        if (user != null && notified.add(user.getId())) {
            notifyUser(user, ticket, type, title, message);
        }
    }

    private void notifyUser(AppUser user, SupportTicket ticket, String type,
            String title, String message) {
        if (user != null) {
            notifications.save(new SupportNotification(user, ticket, type, title, message));
        }
    }

    private List<ContestationView> contestationViews(UUID ticketId) {
        return contestations.findByTicket_IdOrderByCreatedAtAsc(ticketId).stream()
                .map(ContestationView::from).toList();
    }

    private TicketView ticketView(SupportTicket ticket) {
        String tripLabel = null;
        if (ticket.getTripId() != null) {
            tripLabel = trips.findById(ticket.getTripId())
                    .map(trip -> trip.getOriginLabel() + " → " + trip.getDestinationLabel())
                    .orElse("Trip unavailable");
        }
        return TicketView.from(ticket, tripLabel);
    }

    private SupportTicket participantTicket(UUID userId, UUID ticketId) {
        SupportTicket ticket = tickets.findDetailedById(ticketId)
                .orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
        boolean opener = ticket.getUser() != null && ticket.getUser().getId().equals(userId);
        boolean reported = ticket.getReportedUser() != null
                && ticket.getReportedUser().getId().equals(userId);
        boolean tripParticipant = ticket.getReservationId() != null
                ? isReservationParticipant(userId, ticket.getReservationId())
                : ticket.getTripId() != null && isTripParticipant(userId, ticket.getTripId());
        if (!opener && !reported && !tripParticipant) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ticket_access_denied",
                    "You are not allowed to access this support ticket.");
        }
        return ticket;
    }

    private void requireBeforeReview(SupportTicket ticket, String message) {
        if (ticket.getStatus() != SupportTicket.Status.OPEN
                && ticket.getStatus() != SupportTicket.Status.AWAITING_RESPONSE) {
            throw new ApiException(HttpStatus.CONFLICT, "ticket_under_review", message);
        }
    }

    private String safeFileName(String fileName) {
        String cleaned = fileName == null ? "evidence" : fileName.strip();
        cleaned = cleaned.replace('\\', '_').replace('/', '_');
        if (cleaned.isBlank()) cleaned = "evidence";
        return cleaned.length() <= 255 ? cleaned : cleaned.substring(0, 255);
    }

    private void verifyLegacyTripParticipant(UUID userId, UUID tripId) {
        Trip trip = trips.findById(tripId).orElseThrow(() ->
                notFound("trip_not_found", "The selected trip was not found."));
        if (!trip.isDrivenBy(userId) && !isTripPassenger(userId, tripId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "not_trip_participant",
                    "Only participants can report an issue about this trip.");
        }
    }

    private boolean isTripParticipant(UUID userId, UUID tripId) {
        return trips.findById(tripId).map(trip ->
                trip.isDrivenBy(userId) || isTripPassenger(userId, tripId)).orElse(false);
    }

    private boolean isReservationParticipant(UUID userId, UUID reservationId) {
        return reservations.findById(reservationId).map(reservation ->
                reservation.isHeldBy(userId)
                        || reservation.getTrip().isDrivenBy(userId)).orElse(false);
    }

    private boolean isTripPassenger(UUID userId, UUID tripId) {
        return reservations.findByTrip_IdAndStatusIn(
                        tripId, SUPPORT_PARTICIPANT_STATUSES).stream()
                .anyMatch(reservation -> reservation.getPassenger().getId().equals(userId));
    }

    private SupportTicket ownedTicket(UUID userId, UUID ticketId) {
        return tickets.findByIdAndUser_Id(ticketId, userId)
                .orElseThrow(() -> notFound("ticket_not_found", "Support ticket not found."));
    }

    private TicketCategory resolveCategory(UUID categoryId, String categoryName) {
        if (categoryId != null) {
            TicketCategory category = category(categoryId);
            if (category.isActive()) return category;
        } else if (categoryName != null) {
            return categories.findByNameIgnoreCaseAndActiveTrue(categoryName.strip())
                    .orElseThrow(() -> invalidCategory());
        }
        throw invalidCategory();
    }

    private TicketCategory category(UUID categoryId) {
        return categories.findById(categoryId).orElseThrow(() ->
                notFound("category_not_found", "Support category not found."));
    }

    private void validateCategory(CategoryRequest request) {
        if (request.severity() < 1 || request.severity() > 5
                || request.responseDelayHours() < 1
                || request.priority() == null || request.verificationType() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_category",
                    "Severity, priority, response delay and verification type are required.");
        }
    }

    private String clean(String value, int max, String label) {
        String text = value == null ? "" : value.strip();
        if (text.isEmpty() || text.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_ticket",
                    label + " is required and must be no longer than " + max + " characters.");
        }
        return text;
    }

    private ApiException invalidCategory() {
        return new ApiException(HttpStatus.BAD_REQUEST, "invalid_ticket_category",
                "Choose an active support category.");
    }

    private static ApiException notFound(String code, String message) {
        return new ApiException(HttpStatus.NOT_FOUND, code, message);
    }

    public record CategoryRequest(String name, int severity, TicketCategory.Priority priority,
            int responseDelayHours, TicketCategory.VerificationType verificationType,
            boolean active) { }

    public record CategoryView(UUID id, String name, int severity,
            TicketCategory.Priority priority, int responseDelayHours,
            TicketCategory.VerificationType verificationType, boolean active,
            Instant createdAt, Instant updatedAt) {
        public static CategoryView from(TicketCategory category) {
            return new CategoryView(category.getId(), category.getName(), category.getSeverity(),
                    category.getPriority(), category.getResponseDelayHours(),
                    category.getVerificationType(), category.isActive(), category.getCreatedAt(),
                    category.getUpdatedAt());
        }
    }

    public record ReportTargetView(UUID userId, String fullName, UUID reservationId,
            String role) { }

    public record TicketRequest(UUID tripId, UUID reservationId, UUID categoryId,
            String category, String title, String description) { }

    public record UpdateTicketRequest(UUID categoryId, String category, String title,
            String description) { }

    public record DecisionRequest(TicketDecision.Result result, String reason,
            int penaltyPoints) { }

    public record StatusRequest(SupportTicket.Status status, String reason) { }

    public record TicketView(UUID id, String reference, UUID userId, String userName,
            String userEmail, UUID tripId, String tripLabel, UUID reservationId,
            UUID reportedUserId,
            String reportedUserName, String reportedUserRole, UUID categoryId,
            String category, String title, String description,
            java.math.BigDecimal priorityScore, SupportTicket.Status status,
            String resolution, Instant deadline, Instant createdAt, Instant updatedAt) {
        public static TicketView from(SupportTicket ticket, String tripLabel) {
            AppUserView user = AppUserView.from(ticket.getUser());
            return new TicketView(ticket.getId(), ticket.getReference(), user.id(), user.name(),
                    user.email(), ticket.getTripId(), tripLabel, ticket.getReservationId(),
                    ticket.getReportedUser() == null ? null : ticket.getReportedUser().getId(),
                    ticket.getReportedUser() == null ? null
                            : ticket.getReportedUser().getFullName(),
                    ticket.getReportedUser() == null ? null
                            : ticket.getReportedUser().getRole().name(),
                    ticket.getCategoryDefinition().getId(), ticket.getCategory(), ticket.getTitle(),
                    ticket.getDescription(), ticket.getPriorityScore(), ticket.getStatus(),
                    ticket.getResolution(), ticket.getDeadline(), ticket.getCreatedAt(),
                    ticket.getUpdatedAt());
        }

        public static TicketView from(SupportTicket ticket) {
            return from(ticket, null);
        }
    }

    public record AdminTicketDetailsView(TicketView ticket, List<EvidenceView> evidence,
            List<StatementView> statements, List<DecisionView> decisions,
            List<HistoryView> history, List<ContestationView> contestations) { }

    public record EvidenceView(UUID id, UUID ticketId, TicketEvidence.Type type,
            String originalFileName, String contentType, long fileSize, UUID uploadedByUserId,
            String uploadedByName, Instant createdAt) {
        public static EvidenceView from(TicketEvidence item) {
            return new EvidenceView(item.getId(), item.getTicket().getId(), item.getType(),
                    item.getOriginalFileName(), item.getContentType(), item.getFileSize(),
                    item.getUploadedBy() == null ? null : item.getUploadedBy().getId(),
                    item.getUploadedBy() == null ? "System" : item.getUploadedBy().getFullName(),
                    item.getCreatedAt());
        }
    }

    public record EvidenceContent(String fileName, String contentType, byte[] bytes) { }

    public record StatementView(UUID id, UUID ticketId, UUID authorId, String authorName,
            String text, Instant createdAt, Instant updatedAt) {
        public static StatementView from(TicketStatement statement) {
            AppUser author = statement.getAuthor();
            return new StatementView(statement.getId(), statement.getTicket().getId(),
                    author == null ? null : author.getId(),
                    author == null ? "Deleted user" : author.getFullName(),
                    statement.getStatementText(), statement.getCreatedAt(),
                    statement.getUpdatedAt());
        }
    }

    public record DecisionView(UUID id, UUID ticketId, TicketDecision.Result result,
            String reason, int penaltyPoints, UUID decidedBy, boolean decidedBySystem,
            int decisionNumber, boolean finalDecision, Instant decidedAt) {
        public static DecisionView from(TicketDecision decision) {
            return new DecisionView(decision.getId(), decision.getTicket().getId(),
                    decision.getResult(), decision.getReason(), decision.getPenaltyPoints(),
                    decision.getDecidedBy() == null ? null : decision.getDecidedBy().getId(),
                    decision.isDecidedBySystem(), decision.getDecisionNumber(),
                    decision.isFinalDecision(), decision.getDecidedAt());
        }
    }

    public record HistoryView(UUID id, SupportTicket.Status fromStatus,
            SupportTicket.Status toStatus, UUID changedBy, boolean changedBySystem,
            String reason, Instant createdAt) {
        public static HistoryView from(TicketStatusHistory item) {
            return new HistoryView(item.getId(), item.getFromStatus(), item.getToStatus(),
                    item.getChangedBy() == null ? null : item.getChangedBy().getId(),
                    item.isChangedBySystem(), item.getReason(), item.getCreatedAt());
        }
    }

    public record ContestationView(UUID id, UUID ticketId, UUID contestedBy,
            String contestedByName, String reason, Instant createdAt) {
        public static ContestationView from(TicketContestation item) {
            AppUser user = item.getContestedBy();
            return new ContestationView(item.getId(), item.getTicket().getId(),
                    user == null ? null : user.getId(),
                    user == null ? "Deleted user" : user.getFullName(),
                    item.getReason(), item.getCreatedAt());
        }
    }

    public record NotificationView(UUID id, UUID ticketId, String ticketReference,
            String type, String title, String message, boolean read, Instant createdAt) {
        public static NotificationView from(SupportNotification notification) {
            return new NotificationView(notification.getId(),
                    notification.getTicket().getId(),
                    notification.getTicket().getReference(), notification.getType(),
                    notification.getTitle(), notification.getMessage(),
                    notification.getReadAt() != null, notification.getCreatedAt());
        }
    }

    public record UnreadCount(long count) { }

    private record AppUserView(UUID id, String name, String email) {
        static AppUserView from(AppUser user) {
            return user == null
                    ? new AppUserView(null, "Deleted user", null)
                    : new AppUserView(user.getId(), user.getFullName(), user.getEmail());
        }
    }
}
