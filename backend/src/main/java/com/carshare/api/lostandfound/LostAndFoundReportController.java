package com.carshare.api.lostandfound;

import com.carshare.api.security.SessionPrincipal;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/lost-and-found")
public class LostAndFoundReportController {

    private final LostAndFoundReportService service;
    private final LostAndFoundHandoverService handovers;

    public LostAndFoundReportController(
            LostAndFoundReportService service, LostAndFoundHandoverService handovers) {
        this.service = service;
        this.handovers = handovers;
    }

    @GetMapping("/trips")
    public List<LostAndFoundReportService.TripOption> listTrips(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return service.listTrips(principal.userId());
    }

    @GetMapping("/trips/{tripId}/reports")
    public List<LostAndFoundReportService.ReportView> listReports(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("tripId") UUID tripId) {
        return service.listForTrip(principal.userId(), tripId);
    }

    @PostMapping("/trips/{tripId}/reports")
    @ResponseStatus(HttpStatus.CREATED)
    public LostAndFoundReportService.ReportView createReport(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("tripId") UUID tripId,
            @RequestBody CreateReportRequest request) {
        return service.create(
                principal.userId(), tripId, request.type(),
                request.title(), request.description());
    }

    @PutMapping("/reports/{reportId}/resolve")
    public LostAndFoundReportService.ReportView resolveReport(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("reportId") UUID reportId) {
        return service.resolve(principal.userId(), reportId);
    }

    /** A phone matched two reports and asks to start (or rejoin) their handover. */
    @PostMapping("/handovers")
    @ResponseStatus(HttpStatus.CREATED)
    public LostAndFoundHandoverService.HandoverView proposeHandover(
            @AuthenticationPrincipal SessionPrincipal principal,
            @RequestBody ProposeHandoverRequest request) {
        return handovers.propose(
                principal.userId(), request.lostReportId(), request.foundReportId());
    }

    @GetMapping("/handovers/mine")
    public List<LostAndFoundHandoverService.HandoverView> myHandovers(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return handovers.mine(principal.userId());
    }

    @PutMapping("/handovers/{handoverId}/arrange")
    public LostAndFoundHandoverService.HandoverView arrangeHandover(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("handoverId") UUID handoverId,
            @RequestBody ArrangeHandoverRequest request) {
        return handovers.arrange(
                principal.userId(), handoverId, request.meetingPoint(), request.meetingTime());
    }

    @PostMapping("/handovers/{handoverId}/verify")
    public LostAndFoundHandoverService.HandoverView verifyHandover(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("handoverId") UUID handoverId,
            @RequestBody VerifyHandoverRequest request) {
        return handovers.verify(principal.userId(), handoverId, request.code());
    }

    @PostMapping("/handovers/{handoverId}/reject")
    public LostAndFoundHandoverService.HandoverView rejectHandover(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("handoverId") UUID handoverId) {
        return handovers.reject(principal.userId(), handoverId);
    }

    public record ProposeHandoverRequest(UUID lostReportId, UUID foundReportId) {
    }

    public record ArrangeHandoverRequest(String meetingPoint, String meetingTime) {
    }

    public record VerifyHandoverRequest(String code) {
    }

    public record CreateReportRequest(
            LostAndFoundReport.Type type, String title, String description) {
    }
}