package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * The read-only face other modules use. These tests pin the contract they depend on: small
 * records, no entities, and no way to change anything.
 */
@ExtendWith(MockitoExtension.class)
class ReservationQueriesTest {

    @Mock private TripRepository trips;
    @Mock private ReservationRepository reservations;
    @Mock private TripEventRepository tripEvents;
    @Mock private GpsPointRepository gpsPoints;

    private ReservationQueries queries;
    private AppUser driver;
    private AppUser passenger;
    private Trip trip;

    @BeforeEach
    void setUp() {
        queries = new ReservationQueries(trips, reservations, tripEvents, gpsPoints);
        driver = new AppUser("Ahmed Driver", "+21611111111", "ahmed@carshare.tn", "hash",
                UserRole.DRIVER);
        passenger = new AppUser("Mariem Rider", "+21622222222", "mariem@carshare.tn", "hash",
                UserRole.PASSENGER);
        trip = new Trip(driver, null, "Tunis", 36.8, 10.18, "Sousse", 35.82, 10.63,
                Instant.now().plus(2, ChronoUnit.HOURS), 3, new BigDecimal("12.00"), true,
                null, null, 5_400, null);
    }

    @Test
    @DisplayName("tripFacts answers with a record, never the entity")
    void tripFactsIsAPlainRecord() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        ReservationQueries.TripFacts facts = queries.tripFacts(trip.getId()).orElseThrow();

        assertEquals(trip.getId(), facts.tripId());
        assertEquals(driver.getId(), facts.driverId());
        assertEquals("Tunis", facts.originLabel());
        assertEquals("SCHEDULED", facts.status());
        assertEquals(trip.getDepartureTime().plusSeconds(5_400), facts.expectedArrival());
        assertEquals(3, facts.seatsTotal());
    }

    @Test
    @DisplayName("an unknown trip is empty rather than an exception")
    void unknownTripIsEmpty() {
        when(trips.findById(any())).thenReturn(Optional.empty());

        assertTrue(queries.tripFacts(UUID.randomUUID()).isEmpty());
        assertTrue(queries.participants(UUID.randomUUID()).isEmpty());
    }

    @Test
    @DisplayName("participants are the driver first, then the passengers who held a seat")
    void participantsListsBothSides() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        Reservation boarded = new Reservation(trip, passenger, 2, "1234");
        boarded.confirm(Instant.now());
        boarded.recordCheckIn(Instant.now());
        when(reservations.findByTrip_IdAndStatusIn(eq(trip.getId()), any()))
                .thenReturn(List.of(boarded));

        List<ReservationQueries.Participant> people = queries.participants(trip.getId());

        assertEquals(2, people.size());
        assertEquals("DRIVER", people.get(0).role());
        assertEquals(driver.getId(), people.get(0).userId());
        assertEquals("PASSENGER", people.get(1).role());
        assertEquals(passenger.getId(), people.get(1).userId());
        assertTrue(people.get(1).checkedIn());
    }

    @Test
    @DisplayName("wasOnTrip is true for the driver and for a passenger who held a seat")
    void wasOnTripCoversBothSides() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));

        assertTrue(queries.wasOnTrip(trip.getId(), driver.getId()));
    }

    @Test
    @DisplayName("wasOnTrip is false for somebody who had nothing to do with the trip")
    void wasOnTripRejectsStrangers() {
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(reservations.findByTrip_IdAndPassenger_IdAndStatusIn(any(), any(), any()))
                .thenReturn(Optional.empty());

        assertFalse(queries.wasOnTrip(trip.getId(), UUID.randomUUID()));
    }

    @Test
    @DisplayName("a vehicle on a trip that has not finished is still committed")
    void vehicleCommitmentUsesTheUnfinishedStatuses() {
        UUID vehicleId = UUID.randomUUID();
        when(trips.existsByVehicleIdAndStatusIn(vehicleId, TripStatus.UNFINISHED))
                .thenReturn(true);

        assertTrue(queries.vehicleHasUpcomingTrips(vehicleId));
        // A finished or cancelled trip must not hold a car hostage.
        assertFalse(TripStatus.UNFINISHED.contains(TripStatus.COMPLETED));
        assertFalse(TripStatus.UNFINISHED.contains(TripStatus.CANCELLED));
        assertTrue(TripStatus.UNFINISHED.contains(TripStatus.SCHEDULED));
        assertTrue(TripStatus.UNFINISHED.contains(TripStatus.IN_PROGRESS));
    }

    @Test
    @DisplayName("the GPS track comes back in the order the phone recorded it")
    void gpsTrackKeepsRecordedOrder() {
        Instant first = Instant.parse("2026-11-21T07:00:00Z");
        when(gpsPoints.findByTrip_IdOrderByRecordedAtAsc(trip.getId())).thenReturn(List.of(
                new GpsPoint(trip, 36.80, 10.18, 10f, first),
                new GpsPoint(trip, 36.81, 10.19, 11f, first.plusSeconds(4))));

        List<ReservationQueries.TrackPoint> track = queries.gpsTrack(trip.getId());

        assertEquals(2, track.size());
        assertEquals(36.80, track.get(0).lat());
        assertEquals(first.plusSeconds(4), track.get(1).recordedAt());
    }

    @Test
    @DisplayName("events come back oldest first, as plain facts")
    void eventsAreFlattened() {
        when(tripEvents.findByTrip_IdOrderByCreatedAtAsc(trip.getId())).thenReturn(List.of(
                new TripEvent(trip, TripEventType.PUBLISHED, driver.getId(), null, null, null)));

        List<ReservationQueries.EventFact> events = queries.events(trip.getId());

        assertEquals(1, events.size());
        assertEquals("PUBLISHED", events.get(0).type());
        assertEquals(driver.getId(), events.get(0).actorId());
    }
}
