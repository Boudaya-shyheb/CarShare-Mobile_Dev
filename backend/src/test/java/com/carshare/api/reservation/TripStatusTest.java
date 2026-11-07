package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class TripStatusTest {

    @Test
    @DisplayName("allowedNext matches the specified state machine")
    void allowedNextMatchesSpecification() {
        assertEquals(Set.of(TripStatus.DRIVER_EN_ROUTE, TripStatus.CANCELLED),
                TripStatus.SCHEDULED.allowedNext());
        assertEquals(Set.of(TripStatus.DRIVER_ARRIVED, TripStatus.CANCELLED),
                TripStatus.DRIVER_EN_ROUTE.allowedNext());
        assertEquals(Set.of(TripStatus.PICKED_UP), TripStatus.DRIVER_ARRIVED.allowedNext());
        assertEquals(Set.of(TripStatus.IN_PROGRESS), TripStatus.PICKED_UP.allowedNext());
        assertEquals(Set.of(TripStatus.COMPLETED), TripStatus.IN_PROGRESS.allowedNext());
        assertEquals(Set.of(), TripStatus.COMPLETED.allowedNext());
        assertEquals(Set.of(), TripStatus.CANCELLED.allowedNext());
    }

    @Test
    @DisplayName("a trip can no longer move once it is completed or cancelled")
    void terminalStatusesAreFinal() {
        assertTrue(TripStatus.COMPLETED.isFinal());
        assertTrue(TripStatus.CANCELLED.isFinal());
        assertFalse(TripStatus.SCHEDULED.isFinal());
        assertFalse(TripStatus.IN_PROGRESS.isFinal());
    }

    @Test
    @DisplayName("canMoveTo only accepts the declared next statuses")
    void canMoveToRejectsEverythingElse() {
        for (TripStatus from : TripStatus.values()) {
            for (TripStatus to : TripStatus.values()) {
                assertEquals(from.allowedNext().contains(to), from.canMoveTo(to),
                        from + " -> " + to);
            }
        }
    }

    @Test
    @DisplayName("skipping a step or going backwards is refused")
    void shortcutsAreRefused() {
        assertFalse(TripStatus.SCHEDULED.canMoveTo(TripStatus.IN_PROGRESS));
        assertFalse(TripStatus.SCHEDULED.canMoveTo(TripStatus.COMPLETED));
        assertFalse(TripStatus.DRIVER_ARRIVED.canMoveTo(TripStatus.CANCELLED));
        assertFalse(TripStatus.IN_PROGRESS.canMoveTo(TripStatus.DRIVER_ARRIVED));
        assertFalse(TripStatus.COMPLETED.canMoveTo(TripStatus.IN_PROGRESS));
        assertFalse(TripStatus.SCHEDULED.canMoveTo(null));
    }

    @Test
    @DisplayName("reservations are only accepted while the trip is scheduled")
    void onlyScheduledTripsAcceptReservations() {
        for (TripStatus status : TripStatus.values()) {
            assertEquals(status == TripStatus.SCHEDULED, status.acceptsReservations(), status.name());
        }
    }

    @Test
    @DisplayName("positions are accepted from en route until the trip completes")
    void positionsAreAcceptedWhileDriving() {
        assertFalse(TripStatus.SCHEDULED.acceptsPositions());
        assertTrue(TripStatus.DRIVER_EN_ROUTE.acceptsPositions());
        assertTrue(TripStatus.DRIVER_ARRIVED.acceptsPositions());
        assertTrue(TripStatus.PICKED_UP.acceptsPositions());
        assertTrue(TripStatus.IN_PROGRESS.acceptsPositions());
        assertFalse(TripStatus.COMPLETED.acceptsPositions());
        assertFalse(TripStatus.CANCELLED.acceptsPositions());
    }

    @Test
    @DisplayName("every status maps to an event type")
    void everyStatusHasAnEventType() {
        for (TripStatus status : TripStatus.values()) {
            assertNotNull(TripEventType.forStatus(status), status.name());
        }
        assertEquals(TripEventType.PUBLISHED, TripEventType.forStatus(TripStatus.SCHEDULED));
        assertEquals(TripEventType.CANCELLED, TripEventType.forStatus(TripStatus.CANCELLED));
    }
}
