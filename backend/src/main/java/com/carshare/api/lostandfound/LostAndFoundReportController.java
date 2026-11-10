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

    public LostAndFoundReportController(LostAndFoundReportService service) {
        this.service = service;
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

    public record CreateReportRequest(
            LostAndFoundReport.Type type, String title, String description) {
    }
}