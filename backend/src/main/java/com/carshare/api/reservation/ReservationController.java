package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Everything a passenger or driver does to an existing reservation. */
@RestController
@RequestMapping("/api/reservations")
public class ReservationController {
    private final ReservationService reservationService;

    public ReservationController(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @GetMapping("/mine")
    public List<ReservationDtos.ReservationDetail> myReservations(
            @AuthenticationPrincipal SessionPrincipal principal,
            @RequestParam(required = false) String scope) {
        return reservationService.listMine(principal.userId(), scope);
    }

    @PostMapping("/{reservationId}/accept")
    public ReservationDtos.PassengerView accept(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID reservationId) {
        return reservationService.accept(principal.userId(), reservationId);
    }

    @PostMapping("/{reservationId}/refuse")
    public ReservationDtos.PassengerView refuse(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID reservationId) {
        return reservationService.refuse(principal.userId(), reservationId);
    }

    @PostMapping("/{reservationId}/cancel")
    public ReservationDtos.ReservationDetail cancel(
            @AuthenticationPrincipal SessionPrincipal principal, @PathVariable UUID reservationId,
            @Valid @RequestBody ReservationDtos.CancelReservationRequest request) {
        return reservationService.cancel(principal.userId(), reservationId, request.reason());
    }
}
