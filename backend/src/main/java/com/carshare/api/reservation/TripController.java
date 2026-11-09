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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/trips")
public class TripController {
    private final TripService tripService;

    public TripController(TripService tripService) {
        this.tripService = tripService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TripDtos.TripDetail publish(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody TripDtos.PublishTripRequest request) {
        return tripService.publish(principal.userId(), request);
    }

    @GetMapping("/mine")
    public List<TripDtos.TripSummary> myTrips(@AuthenticationPrincipal SessionPrincipal principal,
            @RequestParam(required = false) String scope) {
        return tripService.listMine(principal.userId(), scope);
    }

    @GetMapping("/search")
    public List<TripDtos.TripSearchResult> search(@AuthenticationPrincipal SessionPrincipal principal,
            @RequestParam(required = false) Double originLat,
            @RequestParam(required = false) Double originLng,
            @RequestParam(required = false) Double destinationLat,
            @RequestParam(required = false) Double destinationLng,
            @RequestParam(required = false) String departureTime,
            @RequestParam(required = false) Integer seats,
            @RequestParam(required = false) String sort) {
        return tripService.search(principal.userId(), new TripDtos.SearchRequest(originLat, originLng,
                destinationLat, destinationLng, departureTime, seats, sort));
    }

    @GetMapping("/{tripId}")
    public TripDtos.TripDetail trip(@PathVariable UUID tripId) {
        return tripService.get(tripId);
    }

    @PutMapping("/{tripId}")
    public TripDtos.TripDetail updateTrip(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @Valid @RequestBody TripDtos.UpdateTripRequest request) {
        return tripService.update(principal.userId(), tripId, request);
    }

    @PostMapping("/{tripId}/cancel")
    public TripDtos.TripDetail cancelTrip(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @Valid @RequestBody TripDtos.CancelTripRequest request) {
        return tripService.cancel(principal.userId(), tripId, request.reason());
    }

    @PostMapping("/{tripId}/status")
    public TripDtos.TripDetail changeStatus(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @Valid @RequestBody TripDtos.ChangeStatusRequest request) {
        return tripService.changeStatus(principal.userId(), tripId, request);
    }

    @GetMapping("/{tripId}/events")
    public List<TripDtos.EventView> events(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId) {
        return tripService.listEvents(principal.userId(), tripId);
    }
}
