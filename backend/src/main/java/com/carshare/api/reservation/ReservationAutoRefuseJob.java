package com.carshare.api.reservation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Runs the auto-refuse rule once a minute. All the logic lives in
 * {@link ReservationService#autoRefusePending()}; this class only decides when to call it, so the
 * rule itself can be tested on a fixed clock without a Spring context.
 */
@Component
public class ReservationAutoRefuseJob {
    private static final Logger log = LoggerFactory.getLogger(ReservationAutoRefuseJob.class);
    /** Durations as ISO-8601 text, which an annotation can hold as a constant. */
    private static final String EVERY_MINUTE = "PT1M";

    private final ReservationService reservationService;

    public ReservationAutoRefuseJob(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @Scheduled(fixedDelayString = EVERY_MINUTE, initialDelayString = EVERY_MINUTE)
    public void refuseUnansweredRequests() {
        try {
            int refused = reservationService.autoRefusePending();
            if (refused > 0) {
                log.info("Auto-refused {} unanswered seat request(s).", refused);
            }
        } catch (RuntimeException failure) {
            // A scheduled method that throws stops being rescheduled on some executors, and a
            // database blip must not take the job down for the rest of the run.
            log.error("The auto-refuse job failed; it will run again in a minute.", failure);
        }
    }
}
