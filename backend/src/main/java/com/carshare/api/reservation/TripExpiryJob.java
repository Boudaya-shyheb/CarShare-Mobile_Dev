package com.carshare.api.reservation;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Runs {@link TripExpiryService} every ten minutes; the rule itself lives in the service. */
@Component
public class TripExpiryJob {
    private static final Logger log = LoggerFactory.getLogger(TripExpiryJob.class);
    private static final String EVERY_TEN_MINUTES = "PT10M";

    private final TripExpiryService expiry;

    public TripExpiryJob(TripExpiryService expiry) {
        this.expiry = expiry;
    }

    @Scheduled(fixedDelayString = EVERY_TEN_MINUTES, initialDelayString = "PT1M")
    public void expireTripsNobodyStarted() {
        try {
            int expired = expiry.expireStaleTrips();
            if (expired > 0) {
                log.info("Expired {} trip(s) that were never started.", expired);
            }
        } catch (RuntimeException failure) {
            // Same reasoning as the auto-refuse job: keep the schedule alive through a blip.
            log.error("The trip expiry job failed; it will run again in ten minutes.", failure);
        }
    }
}
