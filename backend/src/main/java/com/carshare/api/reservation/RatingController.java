package com.carshare.api.reservation;

import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
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

/** Ratings left on a finished trip. */
@RestController
@RequestMapping("/api/trips")
public class RatingController {
    private final RatingService ratingService;

    public RatingController(RatingService ratingService) {
        this.ratingService = ratingService;
    }

    /** A passenger rates the driver, or the driver rates one passenger who boarded. */
    @PostMapping("/{tripId}/ratings")
    @ResponseStatus(HttpStatus.CREATED)
    public RatingDtos.RatingView rate(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @Valid @RequestBody RatingDtos.RateRequest request) {
        return ratingService.rate(principal.userId(), tripId, request);
    }

    /** Changes a rating already left, while the 24 h window is open. */
    @PutMapping("/{tripId}/ratings/{toUserId}")
    public RatingDtos.RatingView revise(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId, @PathVariable UUID toUserId,
            @Valid @RequestBody RatingDtos.ReviseRatingRequest request) {
        return ratingService.revise(principal.userId(), tripId, toUserId, request);
    }

    /** Who the caller may rate on this trip, and what they have already left. */
    @GetMapping("/{tripId}/ratings/mine")
    public RatingDtos.MyRatings mine(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID tripId) {
        return ratingService.mine(principal.userId(), tripId);
    }
}
