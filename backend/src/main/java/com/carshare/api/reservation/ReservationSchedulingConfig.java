package com.carshare.api.reservation;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Turns on Spring's scheduler for the auto-refuse job and supplies the clock the reservation
 * service reads the time from.
 *
 * <p>This lives in the reservation package rather than in a shared config class so no other
 * module's files have to change. If another module later needs its own Clock bean, it should mark
 * that one {@code @Primary}.
 */
@Configuration
@EnableScheduling
public class ReservationSchedulingConfig {
    /** Injected everywhere instead of calling Instant.now(), so tests can fix the time. */
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
