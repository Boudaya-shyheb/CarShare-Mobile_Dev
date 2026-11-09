package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * The reservation routes that hang off a trip. Kept apart from TripController so the trip
 * endpoints and the reservation endpoints each stay with their own service.
 */
@RestController
@RequestMapping("/api/trips")
public class TripReservationController {
    private final ReservationService reservationService;

    public TripReservationController(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @PostMapping("/{tripId}/reservations")
    @ResponseStatus(HttpStatus.CREATED)
    public ReservationDtos.ReservationDetail book(
            @AuthenticationPrincipal SessionPrincipal principal, @PathVariable UUID tripId,
            @Valid @RequestBody ReservationDtos.BookRequest request) {
        return reservationService.book(principal.userId(), tripId, request);
    }

    /** Trip owner only, and never with a pickup code. */
    @GetMapping("/{tripId}/reservations")
    public List<ReservationDtos.PassengerView> tripReservations(
            @AuthenticationPrincipal SessionPrincipal principal, @PathVariable UUID tripId) {
        return reservationService.listForTrip(principal.userId(), tripId);
    }
}
