package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** The live tracking routes that hang off a trip. */
@RestController
@RequestMapping("/api/trips")
public class TripTrackingController {
    private final TrackingService trackingService;

    public TripTrackingController(TrackingService trackingService) {
        this.trackingService = trackingService;
    }

    /**
     * Trip owner only. Takes one point while the app is online, or a whole buffer after a dead
     * spot, and answers with the same live view the passengers poll.
     */
    @PostMapping("/{tripId}/positions")
    public TrackingDtos.LiveView reportPositions(
            @AuthenticationPrincipal SessionPrincipal principal, @PathVariable UUID tripId,
            @RequestBody TrackingDtos.ReportPositionsRequest request) {
        return trackingService.reportPositions(principal.userId(), tripId, request);
    }

    /** The driver, or a passenger holding a confirmed seat. Meant to be polled every 5 s. */
    @GetMapping("/{tripId}/live")
    public TrackingDtos.LiveView live(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId) {
        return trackingService.live(principal.userId(), tripId);
    }

    /** The driven track of a finished trip, for the replay on the completion screen. */
    @GetMapping("/{tripId}/track")
    public List<TrackingDtos.TrackPoint> track(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId) {
        return trackingService.track(principal.userId(), tripId);
    }
}
