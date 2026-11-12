package com.carshare.api.support;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.google.ortools.Loader;
import com.google.ortools.sat.CpModel;
import com.google.ortools.sat.CpSolver;
import com.google.ortools.sat.CpSolverStatus;
import com.google.ortools.sat.BoolVar;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TicketAssignmentService {
    private static final List<SupportTicket.Status> ACTIVE = List.of(
            SupportTicket.Status.OPEN, SupportTicket.Status.AWAITING_RESPONSE,
            SupportTicket.Status.UNDER_REVIEW, SupportTicket.Status.CONTESTED);
    private final SupportTicketRepository tickets;
    private final SupportAgentProfileRepository profiles;
    private final TicketAssignmentProposalRepository proposals;
    private final UserRepository users;

    public TicketAssignmentService(SupportTicketRepository tickets,
            SupportAgentProfileRepository profiles,
            TicketAssignmentProposalRepository proposals, UserRepository users) {
        this.tickets = tickets; this.profiles = profiles; this.proposals = proposals; this.users = users;
    }

    @Transactional
    public AssignmentView propose(UUID ticketId) {
        SupportTicket ticket = ticket(ticketId);
        ensureAdminProfiles();
        List<Candidate> candidates = profiles.findAllByOrderByUser_FullNameAsc().stream()
                .filter(SupportAgentProfile::isAvailable)
                .filter(p -> p.getUser().getRole() == UserRole.ADMIN)
                .filter(p -> ticket.getUser() == null || !p.getUser().getId().equals(ticket.getUser().getId()))
                .filter(p -> ticket.getReportedUser() == null
                        || !p.getUser().getId().equals(ticket.getReportedUser().getId()))
                .map(p -> candidate(ticket, p)).filter(c -> c.openTickets() < c.profile().getCapacity())
                .toList();
        if (candidates.isEmpty()) throw new ApiException(HttpStatus.CONFLICT,
                "support_agent_unavailable", "No available support agent has remaining capacity.");
        Selection selected;
        try { selected = solve(candidates); }
        catch (Throwable error) { selected = fallback(candidates); }
        Candidate candidate = candidates.get(selected.index());
        String explanation = "Open tickets: " + candidate.openTickets()
                + "/" + candidate.profile().getCapacity() + ". Skill match: "
                + (candidate.skillMatch() ? "yes" : "general fallback") + ".";
        TicketAssignmentProposal saved = proposals.save(new TicketAssignmentProposal(ticket,
                candidate.profile().getUser(), selected.algorithm(), candidate.cost(), explanation));
        return AssignmentView.from(saved);
    }

    @Transactional
    public AssignmentView confirm(UUID ticketId, UUID proposalId) {
        TicketAssignmentProposal proposal = proposals.findByIdAndTicket_Id(proposalId, ticketId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "assignment_not_found", "Assignment proposal not found."));
        if (proposal.getStatus() != TicketAssignmentProposal.Status.PROPOSED) {
            throw new ApiException(HttpStatus.CONFLICT, "assignment_already_processed",
                    "This assignment proposal has already been processed.");
        }
        proposal.getTicket().assignTo(proposal.getAgent());
        proposal.confirm();
        return AssignmentView.from(proposal);
    }

    @Transactional(readOnly = true)
    public List<AssignmentView> history(UUID ticketId) {
        ticket(ticketId);
        return proposals.findByTicket_IdOrderByCreatedAtDesc(ticketId).stream()
                .map(AssignmentView::from).toList();
    }

    @Transactional(readOnly = true)
    public List<AgentView> agents() {
        return profiles.findAllByOrderByUser_FullNameAsc().stream().map(p -> new AgentView(
                p.getUser().getId(), p.getUser().getFullName(), p.isAvailable(), p.getSkills(),
                p.getCapacity(), tickets.countByAssignedAgent_IdAndStatusIn(p.getUser().getId(), ACTIVE)))
                .toList();
    }

    @Transactional
    public AgentView updateAgent(UUID userId, boolean available, String skills, int capacity) {
        if (capacity < 1 || capacity > 100) throw new ApiException(HttpStatus.BAD_REQUEST,
                "invalid_agent_capacity", "Capacity must be between 1 and 100.");
        AppUser user = users.findById(userId).filter(u -> u.getRole() == UserRole.ADMIN)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                        "support_agent_not_found", "Administrator not found."));
        SupportAgentProfile profile = profiles.findById(userId)
                .orElseGet(() -> new SupportAgentProfile(user));
        String cleanSkills = skills == null || skills.isBlank() ? "GENERAL" : skills.strip();
        profile.update(available, cleanSkills.substring(0, Math.min(500, cleanSkills.length())), capacity);
        profiles.save(profile);
        return new AgentView(userId, user.getFullName(), available, profile.getSkills(), capacity,
                tickets.countByAssignedAgent_IdAndStatusIn(userId, ACTIVE));
    }

    private Candidate candidate(SupportTicket ticket, SupportAgentProfile profile) {
        long open = tickets.countByAssignedAgent_IdAndStatusIn(profile.getUser().getId(), ACTIVE);
        String skills = profile.getSkills().toLowerCase(Locale.ROOT);
        String category = ticket.getCategory().toLowerCase(Locale.ROOT);
        boolean match = skills.contains("general") || skills.contains(category);
        int cost = Math.toIntExact(open * 100L) + (match ? 0 : 40);
        return new Candidate(profile, open, match, cost);
    }

    private Selection solve(List<Candidate> candidates) {
        Loader.loadNativeLibraries();
        CpModel model = new CpModel();
        BoolVar[] selected = new BoolVar[candidates.size()];
        for (int i = 0; i < candidates.size(); i++) selected[i] = model.newBoolVar("agent_" + i);
        model.addExactlyOne(selected);
        long[] costs = candidates.stream().mapToLong(Candidate::cost).toArray();
        model.minimize(com.google.ortools.sat.LinearExpr.weightedSum(selected, costs));
        CpSolver solver = new CpSolver();
        CpSolverStatus status = solver.solve(model);
        if (status != CpSolverStatus.OPTIMAL && status != CpSolverStatus.FEASIBLE) {
            throw new IllegalStateException("No OR-Tools assignment solution.");
        }
        for (int i = 0; i < selected.length; i++) if (solver.value(selected[i]) == 1) {
            return new Selection(i, "OR_TOOLS_CP_SAT");
        }
        throw new IllegalStateException("No selected agent.");
    }

    private Selection fallback(List<Candidate> candidates) {
        List<Integer> indexes = new ArrayList<>();
        for (int i = 0; i < candidates.size(); i++) indexes.add(i);
        int index = indexes.stream().min(Comparator.comparingInt(i -> candidates.get(i).cost()))
                .orElseThrow();
        return new Selection(index, "DETERMINISTIC_FALLBACK");
    }

    private void ensureAdminProfiles() {
        for (AppUser admin : users.findAllByRoleForUpdate(UserRole.ADMIN)) {
            if (!profiles.existsById(admin.getId())) profiles.save(new SupportAgentProfile(admin));
        }
    }

    private SupportTicket ticket(UUID ticketId) {
        return tickets.findDetailedById(ticketId).orElseThrow(() -> new ApiException(
                HttpStatus.NOT_FOUND, "ticket_not_found", "Support ticket not found."));
    }

    private record Candidate(SupportAgentProfile profile, long openTickets,
            boolean skillMatch, int cost) { }
    private record Selection(int index, String algorithm) { }
    public record AgentView(UUID userId, String name, boolean available, String skills,
            int capacity, long openTickets) { }
    public record AssignmentView(UUID id, UUID agentId, String agentName, String algorithm,
            int score, TicketAssignmentProposal.Status status, String explanation,
            java.time.Instant createdAt, java.time.Instant confirmedAt) {
        static AssignmentView from(TicketAssignmentProposal item) {
            return new AssignmentView(item.getId(), item.getAgent().getId(),
                    item.getAgent().getFullName(), item.getAlgorithm(), item.getScore(),
                    item.getStatus(), item.getExplanation(), item.getCreatedAt(), item.getConfirmedAt());
        }
    }
}
