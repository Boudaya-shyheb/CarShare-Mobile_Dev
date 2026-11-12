package com.carshare.api.support;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin/support")
public class SupportAdvancedController {
    private final SupportTicketRepository tickets;
    private final TicketPriorityService priority;
    private final TicketEscalationEventRepository escalations;
    private final TicketAssignmentService assignments;
    private final SupportExternalAnalysisService external;

    public SupportAdvancedController(SupportTicketRepository tickets,
            TicketPriorityService priority, TicketEscalationEventRepository escalations,
            TicketAssignmentService assignments, SupportExternalAnalysisService external) {
        this.tickets = tickets; this.priority = priority; this.escalations = escalations;
        this.assignments = assignments; this.external = external;
    }

    @GetMapping("/tickets/{ticketId}/advanced")
    public AdvancedView advanced(@PathVariable UUID ticketId) {
        SupportTicket ticket = ticket(ticketId);
        return view(ticket);
    }

    @PostMapping("/tickets/{ticketId}/analysis/refresh")
    public AdvancedView refreshAnalysis(@PathVariable UUID ticketId) {
        SupportTicket ticket = ticket(ticketId);
        priority.refresh(ticket);
        return view(ticket);
    }

    @PostMapping("/tickets/{ticketId}/assignments/propose")
    @ResponseStatus(HttpStatus.CREATED)
    public TicketAssignmentService.AssignmentView propose(@PathVariable UUID ticketId) {
        return assignments.propose(ticketId);
    }

    @PostMapping("/tickets/{ticketId}/assignments/{proposalId}/confirm")
    public TicketAssignmentService.AssignmentView confirm(@PathVariable UUID ticketId,
            @PathVariable UUID proposalId) {
        return assignments.confirm(ticketId, proposalId);
    }

    @GetMapping("/agents")
    public List<TicketAssignmentService.AgentView> agents() { return assignments.agents(); }

    @PutMapping("/agents/{userId}")
    public TicketAssignmentService.AgentView updateAgent(@PathVariable UUID userId,
            @Valid @RequestBody AgentRequest request) {
        return assignments.updateAgent(userId, request.available(), request.skills(), request.capacity());
    }

    @PostMapping("/tickets/{ticketId}/evidence/{evidenceId}/analyze")
    public SupportExternalAnalysisService.EvidenceAnalysisView analyzeEvidence(
            @PathVariable UUID ticketId, @PathVariable UUID evidenceId) {
        return external.analyzeEvidence(ticketId, evidenceId);
    }

    @PostMapping("/tickets/{ticketId}/weather/refresh")
    public SupportExternalAnalysisService.WeatherView refreshWeather(@PathVariable UUID ticketId) {
        return external.refreshWeather(ticketId);
    }

    @PostMapping("/tickets/{ticketId}/geo/refresh")
    public SupportExternalAnalysisService.GeoView refreshGeo(@PathVariable UUID ticketId) {
        return external.refreshGeo(ticketId);
    }

    private AdvancedView view(SupportTicket ticket) {
        List<EscalationView> eventViews = escalations
                .findByTicket_IdOrderByCreatedAtAsc(ticket.getId()).stream()
                .map(e -> new EscalationView(e.getType().name(), e.getMessage(), e.getCreatedAt()))
                .toList();
        return new AdvancedView(priority.view(ticket), eventViews,
                assignments.history(ticket.getId()), external.evidenceAnalyses(ticket.getId()),
                external.weather(ticket.getId()).orElse(null),
                external.geo(ticket.getId()).orElse(null),
                ticket.getAssignedAgent() == null ? null : ticket.getAssignedAgent().getId(),
                ticket.getAssignedAgent() == null ? null : ticket.getAssignedAgent().getFullName());
    }

    private SupportTicket ticket(UUID id) {
        return tickets.findDetailedById(id).orElseThrow(() -> new com.carshare.api.common.ApiException(
                HttpStatus.NOT_FOUND, "ticket_not_found", "Support ticket not found."));
    }

    public record AgentRequest(boolean available, @NotBlank String skills,
            @Min(1) @Max(100) int capacity) { }
    public record EscalationView(String type, String message, Instant createdAt) { }
    public record AdvancedView(TicketPriorityService.Analysis analysis,
            List<EscalationView> escalations,
            List<TicketAssignmentService.AssignmentView> assignments,
            List<SupportExternalAnalysisService.EvidenceAnalysisView> evidenceAnalyses,
            SupportExternalAnalysisService.WeatherView weather,
            SupportExternalAnalysisService.GeoView geo,
            UUID assignedAgentId, String assignedAgentName) { }
}
