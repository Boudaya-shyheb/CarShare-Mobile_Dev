package com.carshare.api.support;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/support/tickets")
public class SupportController {
    private final SupportService support;
    public SupportController(SupportService support) { this.support = support; }

    @GetMapping
    public List<SupportService.TicketView> myTickets(@AuthenticationPrincipal SessionPrincipal principal) {
        return support.myTickets(principal.userId());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public SupportService.TicketView create(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody CreateTicketRequest request) {
        return support.create(principal.userId(), new SupportService.TicketRequest(request.tripId(),
                request.category(), request.title(), request.description()));
    }

    public record CreateTicketRequest(UUID tripId, @NotBlank @Size(max=60) String category,
            @NotBlank @Size(max=120) String title, @NotBlank @Size(max=1500) String description) { }
}
