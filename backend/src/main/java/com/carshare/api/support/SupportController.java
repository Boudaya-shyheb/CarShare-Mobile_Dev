package com.carshare.api.support;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/support/tickets")
public class SupportController {
    private final SupportService support;
    public SupportController(SupportService support) { this.support = support; }

    @GetMapping
    public List<SupportService.TicketView> myTickets(@AuthenticationPrincipal SessionPrincipal principal) {
        return support.myTickets(principal.userId());
    }

    @GetMapping("/{ticketId}")
    public SupportService.TicketView ticket(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.myTicket(principal.userId(), ticketId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.TicketView create(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody CreateTicketRequest request) {
        return support.create(principal.userId(), new SupportService.TicketRequest(request.tripId(),
                request.reservationId(), request.categoryId(), request.category(),
                request.title(), request.description()));
    }

    @PutMapping("/{ticketId}")
    public SupportService.TicketView update(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId, @Valid @RequestBody UpdateTicketRequest request) {
        return support.update(principal.userId(), ticketId, new SupportService.UpdateTicketRequest(
                request.categoryId(), request.category(), request.title(), request.description()));
    }

    @DeleteMapping("/{ticketId}")
    public SupportService.TicketView withdraw(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.withdraw(principal.userId(), ticketId);
    }

    @GetMapping("/{ticketId}/evidence")
    public List<SupportService.EvidenceView> evidence(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.evidence(principal.userId(), ticketId);
    }

    @PostMapping(value = "/{ticketId}/evidence", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.EvidenceView addEvidence(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId,
            @RequestParam("type") TicketEvidence.Type type,
            @RequestPart("file") MultipartFile file) {
        try {
            return support.addEvidence(principal.userId(), ticketId, type,
                    file.getOriginalFilename(), file.getBytes());
        } catch (java.io.IOException exception) {
            throw new com.carshare.api.common.ApiException(HttpStatus.BAD_REQUEST,
                    "invalid_evidence", "The selected evidence file could not be read.");
        }
    }

    @GetMapping("/{ticketId}/evidence/{evidenceId}/file")
    public ResponseEntity<byte[]> evidenceFile(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId, @PathVariable UUID evidenceId) {
        SupportService.EvidenceContent content =
                support.evidenceContent(principal.userId(), ticketId, evidenceId);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(content.contentType()))
                .cacheControl(CacheControl.noStore())
                .header("X-Content-Type-Options", "nosniff")
                .body(content.bytes());
    }

    @DeleteMapping("/{ticketId}/evidence/{evidenceId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteEvidence(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId, @PathVariable UUID evidenceId) {
        support.deleteEvidence(principal.userId(), ticketId, evidenceId);
    }

    @GetMapping("/{ticketId}/statements")
    public List<SupportService.StatementView> statements(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.statements(principal.userId(), ticketId);
    }

    @PostMapping("/{ticketId}/statements")
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.StatementView addStatement(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId, @Valid @RequestBody StatementRequest request) {
        return support.addStatement(principal.userId(), ticketId, request.text());
    }

    @PutMapping("/{ticketId}/statements/mine")
    public SupportService.StatementView updateStatement(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId, @Valid @RequestBody StatementRequest request) {
        return support.updateStatement(principal.userId(), ticketId, request.text());
    }

    @GetMapping("/{ticketId}/decisions")
    public List<SupportService.DecisionView> decisions(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.decisions(principal.userId(), ticketId);
    }

    @GetMapping("/{ticketId}/history")
    public List<SupportService.HistoryView> history(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.history(principal.userId(), ticketId);
    }

    @GetMapping("/{ticketId}/contestations")
    public List<SupportService.ContestationView> contestations(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId) {
        return support.contestations(principal.userId(), ticketId);
    }

    @PostMapping("/{ticketId}/contestations")
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.ContestationView contest(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID ticketId,
            @Valid @RequestBody ContestationRequest request) {
        return support.contest(principal.userId(), ticketId, request.reason());
    }

    public record CreateTicketRequest(UUID tripId, UUID reservationId, UUID categoryId,
            @Size(max=60) String category,
            @NotBlank @Size(max=120) String title, @NotBlank @Size(max=1500) String description) { }

    public record UpdateTicketRequest(UUID categoryId, @Size(max=60) String category,
            @NotBlank @Size(max=120) String title,
            @NotBlank @Size(max=1500) String description) { }

    public record StatementRequest(@NotBlank @Size(max = 2000) String text) { }
    public record ContestationRequest(@NotBlank @Size(max = 1000) String reason) { }
}
