package com.carshare.api.lostandfound;

import com.carshare.api.common.ApiException;
import com.carshare.api.security.SessionPrincipal;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

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

    /** The same report, sent as a form so it can carry a photo (JPG, PNG or WebP, 2 MB at most). */
    @PostMapping(value = "/trips/{tripId}/reports", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public LostAndFoundReportService.ReportView createReportWithPhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("tripId") UUID tripId,
            @RequestParam("type") LostAndFoundReport.Type type,
            @RequestParam("title") String title,
            @RequestParam("description") String description,
            @RequestPart(value = "photo", required = false) MultipartFile photo) {
        try {
            return service.create(principal.userId(), tripId, type, title, description,
                    photo == null ? null : photo.getBytes());
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo", "The photo could not be read.");
        }
    }

    /** One report by id, for a notification whose trip is no longer in the trip list. */
    @GetMapping("/reports/{reportId}")
    public LostAndFoundReportService.ReportView reportById(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("reportId") UUID reportId) {
        return service.reportById(principal.userId(), reportId);
    }

    /** The report's photo: only for the two people it concerns, and for admins. */
    @GetMapping("/reports/{reportId}/photo")
    public ResponseEntity<byte[]> reportPhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable("reportId") UUID reportId) {
        LostAndFoundReportService.PhotoContent photo = service.photoOf(principal.userId(), reportId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(photo.contentType()))
                .cacheControl(CacheControl.noStore()).header("X-Content-Type-Options", "nosniff")
                .body(photo.bytes());
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

    /** "Not my item" on a match nobody confirmed: recorded, without starting a handover. */
    @PostMapping("/handovers/reject")
    public LostAndFoundHandoverService.HandoverView rejectPair(
            @AuthenticationPrincipal SessionPrincipal principal,
            @RequestBody ProposeHandoverRequest request) {
        return handovers.rejectPair(
                principal.userId(), request.lostReportId(), request.foundReportId());
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