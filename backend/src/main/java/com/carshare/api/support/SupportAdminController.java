package com.carshare.api.support;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/support")
public class SupportAdminController {
    private final SupportService support;

    public SupportAdminController(SupportService support) { this.support = support; }

    @GetMapping("/categories")
    public List<SupportService.CategoryView> categories() { return support.allCategories(); }

    @PostMapping("/categories")
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.CategoryView createCategory(@Valid @RequestBody CategoryRequest request) {
        return support.createCategory(request.toService());
    }

    @PutMapping("/categories/{categoryId}")
    public SupportService.CategoryView updateCategory(@PathVariable UUID categoryId,
            @Valid @RequestBody CategoryRequest request) {
        return support.updateCategory(categoryId, request.toService());
    }

    @DeleteMapping("/categories/{categoryId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteCategory(@PathVariable UUID categoryId) {
        support.deleteOrDeactivateCategory(categoryId);
    }

    @GetMapping("/tickets")
    public List<SupportService.TicketView> tickets() { return support.allTickets(); }

    @GetMapping("/tickets/{ticketId}")
    public SupportService.AdminTicketDetailsView ticket(@PathVariable UUID ticketId) {
        return support.adminTicketDetails(ticketId);
    }

    @GetMapping("/tickets/{ticketId}/evidence/{evidenceId}/file")
    public ResponseEntity<byte[]> evidenceFile(@PathVariable UUID ticketId,
            @PathVariable UUID evidenceId) {
        SupportService.EvidenceContent content =
                support.adminEvidenceContent(ticketId, evidenceId);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(content.contentType()))
                .cacheControl(CacheControl.noStore())
                .header("X-Content-Type-Options", "nosniff")
                .body(content.bytes());
    }

    @PostMapping("/tickets/{ticketId}/decisions")
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.DecisionView decide(
            @org.springframework.security.core.annotation.AuthenticationPrincipal
            com.carshare.api.security.SessionPrincipal principal,
            @PathVariable UUID ticketId, @Valid @RequestBody DecisionRequest request) {
        return support.decide(principal.userId(), ticketId,
                new SupportService.DecisionRequest(request.result(), request.reason(),
                        request.penaltyPoints()));
    }

    @PutMapping("/tickets/{ticketId}/status")
    public SupportService.TicketView changeStatus(
            @org.springframework.security.core.annotation.AuthenticationPrincipal
            com.carshare.api.security.SessionPrincipal principal,
            @PathVariable UUID ticketId, @Valid @RequestBody StatusRequest request) {
        return support.changeStatus(principal.userId(), ticketId,
                request.status(), request.reason());
    }

    @GetMapping("/tickets/{ticketId}/contestations")
    public List<SupportService.ContestationView> contestations(@PathVariable UUID ticketId) {
        return support.contestationsForAdmin(ticketId);
    }

    public record CategoryRequest(@NotBlank @Size(max = 60) String name,
            @Min(1) @Max(5) int severity,
            @NotNull TicketCategory.Priority priority,
            @Positive int responseDelayHours,
            @NotNull TicketCategory.VerificationType verificationType,
            boolean active) {
        SupportService.CategoryRequest toService() {
            return new SupportService.CategoryRequest(name, severity, priority,
                    responseDelayHours, verificationType, active);
        }
    }

    public record DecisionRequest(@NotNull TicketDecision.Result result,
            @NotBlank @Size(max = 1500) String reason,
            @Min(0) @Max(12) int penaltyPoints) { }

    public record StatusRequest(@NotNull SupportTicket.Status status,
            @NotBlank @Size(max = 500) String reason) { }
}
