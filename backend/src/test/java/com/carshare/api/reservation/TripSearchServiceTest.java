package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
class TripSearchServiceTest {
    private static final double WANTED_ORIGIN_LAT = 36.8065;
    private static final double WANTED_ORIGIN_LNG = 10.1815;
    private static final double WANTED_DESTINATION_LAT = 35.8256;
    private static final double WANTED_DESTINATION_LNG = 10.6360;

    @Mock private TripRepository trips;
    @Mock private TripEventRepository tripEvents;
    @Mock private UserRepository users;
    @Mock private ReservationService reservationService;

    private TripService service;
    private AppUser otherDriver;
    private UUID searcherId;
    private Instant wantedDeparture;

    @BeforeEach
    void setUp() {
        service = new TripService(trips, tripEvents, users, reservationService);
        otherDriver = new AppUser("Ahmed Driver", "+21611111111", "ahmed@carshare.tn", "hash", UserRole.DRIVER);
        searcherId = UUID.randomUUID();
        wantedDeparture = Instant.now().plus(5, ChronoUnit.HOURS).truncatedTo(ChronoUnit.MINUTES);
    }

    // --- parameter validation ---------------------------------------------------------------

    @Test
    @DisplayName("a missing coordinate is reported as an invalid search")
    void rejectsMissingCoordinate() {
        TripDtos.SearchRequest request = new TripDtos.SearchRequest(null, WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture.toString(), 1, null);

        ApiException error = assertThrows(ApiException.class, () -> service.search(searcherId, request));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_search", error.getCode());
        verifyNoInteractions(trips);
    }

    @Test
    @DisplayName("an out-of-range coordinate is reported as invalid coordinates")
    void rejectsImpossibleCoordinate() {
        TripDtos.SearchRequest request = new TripDtos.SearchRequest(95d, WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture.toString(), 1, null);

        ApiException error = assertThrows(ApiException.class, () -> service.search(searcherId, request));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_coordinates", error.getCode());
    }

    @Test
    @DisplayName("searching from a point to itself is refused")
    void rejectsSameOriginAndDestination() {
        TripDtos.SearchRequest request = new TripDtos.SearchRequest(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG,
                WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, wantedDeparture.toString(), 1, null);

        ApiException error = assertThrows(ApiException.class, () -> service.search(searcherId, request));

        assertEquals("same_origin_and_destination", error.getCode());
    }

    @Test
    @DisplayName("a missing departure time is reported as an invalid search")
    void rejectsMissingDepartureTime() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.search(searcherId, request(null, 1, null)));

        assertEquals("invalid_search", error.getCode());
    }

    @Test
    @DisplayName("a departure time that is not an ISO instant is reported as an invalid search")
    void rejectsMalformedDepartureTime() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.search(searcherId, request("next tuesday", 1, null)));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("invalid_search", error.getCode());
    }

    @Test
    @DisplayName("a seat count outside 1 to 8 is refused")
    void rejectsImpossibleSeatCount() {
        assertEquals("invalid_search", assertThrows(ApiException.class,
                () -> service.search(searcherId, request(wantedDeparture.toString(), 0, null))).getCode());
        assertEquals("invalid_search", assertThrows(ApiException.class,
                () -> service.search(searcherId, request(wantedDeparture.toString(), 9, null))).getCode());
    }

    @Test
    @DisplayName("an unknown sort order is refused")
    void rejectsUnknownSortOrder() {
        ApiException error = assertThrows(ApiException.class,
                () -> service.search(searcherId, request(wantedDeparture.toString(), 1, "nearest")));

        assertEquals("invalid_search", error.getCode());
    }

    // --- the SQL pre-filter -----------------------------------------------------------------

    @Test
    @DisplayName("the hard filters and both bounding boxes are pushed into the query")
    void pushesHardFiltersIntoTheQuery() {
        givenCandidates();

        service.search(searcherId, request(wantedDeparture.toString(), 2, null));

        ArgumentCaptor<Double> box = ArgumentCaptor.forClass(Double.class);
        verify(trips).searchCandidates(eq(TripStatus.SCHEDULED), any(),
                eq(wantedDeparture.minus(Duration.ofHours(3))),
                eq(wantedDeparture.plus(Duration.ofHours(3))),
                eq(2), eq(searcherId),
                box.capture(), box.capture(), box.capture(), box.capture(),
                box.capture(), box.capture(), box.capture(), box.capture());

        double latDelta = GeoUtils.latitudeDelta(2_000);
        double originLngDelta = GeoUtils.longitudeDelta(2_000, WANTED_ORIGIN_LAT);
        double destinationLngDelta = GeoUtils.longitudeDelta(2_000, WANTED_DESTINATION_LAT);
        List<Double> bounds = box.getAllValues();
        assertEquals(WANTED_ORIGIN_LAT - latDelta, bounds.get(0), 1e-9);
        assertEquals(WANTED_ORIGIN_LAT + latDelta, bounds.get(1), 1e-9);
        assertEquals(WANTED_ORIGIN_LNG - originLngDelta, bounds.get(2), 1e-9);
        assertEquals(WANTED_ORIGIN_LNG + originLngDelta, bounds.get(3), 1e-9);
        assertEquals(WANTED_DESTINATION_LAT - latDelta, bounds.get(4), 1e-9);
        assertEquals(WANTED_DESTINATION_LAT + latDelta, bounds.get(5), 1e-9);
        assertEquals(WANTED_DESTINATION_LNG - destinationLngDelta, bounds.get(6), 1e-9);
        assertEquals(WANTED_DESTINATION_LNG + destinationLngDelta, bounds.get(7), 1e-9);
    }

    @Test
    @DisplayName("the default sort and seat count are best and one")
    void defaultsToBestAndOneSeat() {
        givenCandidates();

        service.search(searcherId, request(wantedDeparture.toString(), null, null));

        verify(trips).searchCandidates(eq(TripStatus.SCHEDULED), any(), any(), any(), eq(1),
                eq(searcherId), anyDouble(), anyDouble(), anyDouble(), anyDouble(), anyDouble(),
                anyDouble(), anyDouble(), anyDouble());
    }

    // --- exclusion rules --------------------------------------------------------------------

    @Test
    @DisplayName("the passenger never sees their own trip")
    void excludesTripsDrivenBySearcher() {
        AppUser searcherAsDriver = new AppUser("Me", "+21622222222", "me@carshare.tn", "hash", UserRole.DRIVER);
        Trip ownTrip = new Trip(searcherAsDriver, null, "Origin", WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG,
                "Destination", WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, 4,
                new BigDecimal("12.00"), false, null, null, null);
        givenCandidates(ownTrip, perfectTrip());

        List<TripDtos.TripSearchResult> results =
                service.search(searcherAsDriver.getId(), request(wantedDeparture.toString(), 1, null));

        assertEquals(1, results.size());
        assertEquals(otherDriver.getId(), results.get(0).driverId());
    }

    @Test
    @DisplayName("a trip that already started is excluded")
    void excludesTripsThatAreNoLongerScheduled() {
        Trip started = perfectTrip();
        started.applyStatus(TripStatus.DRIVER_EN_ROUTE);
        givenCandidates(started);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 1, null)).isEmpty());
    }

    @Test
    @DisplayName("a trip without enough free seats is excluded")
    void excludesTripsWithTooFewSeats() {
        Trip single = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, wantedDeparture, "12.00", 1);
        givenCandidates(single);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 2, null)).isEmpty());
        assertEquals(1, service.search(searcherId, request(wantedDeparture.toString(), 1, null)).size());
    }

    @Test
    @DisplayName("a trip whose departure has passed is excluded")
    void excludesTripsAlreadyGone() {
        Trip gone = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, Instant.now().minus(10, ChronoUnit.MINUTES), "12.00", 4);
        givenCandidates(gone);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 1, null)).isEmpty());
    }

    @Test
    @DisplayName("a pickup point further than two kilometres away is excluded")
    void excludesTripsWithADistantPickup() {
        Trip farPickup = tripAt(latPlus(WANTED_ORIGIN_LAT, 3_000), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, "12.00", 4);
        givenCandidates(farPickup);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 1, null)).isEmpty());
    }

    @Test
    @DisplayName("a drop-off point further than two kilometres away is excluded")
    void excludesTripsWithADistantDropoff() {
        Trip farDropoff = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG,
                latPlus(WANTED_DESTINATION_LAT, 3_000), WANTED_DESTINATION_LNG, wantedDeparture,
                "12.00", 4);
        givenCandidates(farDropoff);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 1, null)).isEmpty());
    }

    @Test
    @DisplayName("a trip scoring below fifty is excluded even though it is inside the radius")
    void excludesWeakMatches() {
        // 1900 m from both ends and 55 minutes late scores 20.
        Trip weak = tripAt(latPlus(WANTED_ORIGIN_LAT, 1_900), WANTED_ORIGIN_LNG,
                latPlus(WANTED_DESTINATION_LAT, 1_900), WANTED_DESTINATION_LNG,
                wantedDeparture.plus(55, ChronoUnit.MINUTES), "12.00", 4);
        givenCandidates(weak);

        assertTrue(service.search(searcherId, request(wantedDeparture.toString(), 1, null)).isEmpty());
    }

    // --- the result -------------------------------------------------------------------------

    @Test
    @DisplayName("an exact match comes back with zero distances and a score of 100")
    void reportsDistancesTimeGapAndScore() {
        givenCandidates(perfectTrip());

        TripDtos.TripSearchResult result =
                service.search(searcherId, request(wantedDeparture.toString(), 1, null)).get(0);

        assertEquals(0, result.pickupDistanceM());
        assertEquals(0, result.dropoffDistanceM());
        assertEquals(0, result.timeGapMin());
        assertEquals(100, result.matchScore());
        assertEquals(otherDriver.getId(), result.driverId());
        assertEquals("Ahmed Driver", result.driverName());
        assertEquals(4, result.seatsAvailable());
        assertEquals(new BigDecimal("12.00"), result.pricePerSeat());
    }

    @Test
    @DisplayName("the measured distances and time gap match what was asked for")
    void measuresDistancesAndTimeGap() {
        Trip nearby = tripAt(latPlus(WANTED_ORIGIN_LAT, 500), WANTED_ORIGIN_LNG,
                latPlus(WANTED_DESTINATION_LAT, 500), WANTED_DESTINATION_LNG,
                wantedDeparture.plus(15, ChronoUnit.MINUTES), "12.00", 4);
        givenCandidates(nearby);

        TripDtos.TripSearchResult result =
                service.search(searcherId, request(wantedDeparture.toString(), 1, null)).get(0);

        assertEquals(500, result.pickupDistanceM(), 2);
        assertEquals(500, result.dropoffDistanceM(), 2);
        assertEquals(15, result.timeGapMin());
        assertEquals(79, result.matchScore());
    }

    @Test
    @DisplayName("a trip leaving before the requested time is just as good as one leaving after")
    void timeGapIsMeasuredInBothDirections() {
        Trip early = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, wantedDeparture.minus(20, ChronoUnit.MINUTES), "12.00", 4);
        Trip late = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, wantedDeparture.plus(20, ChronoUnit.MINUTES), "12.00", 4);
        givenCandidates(late, early);

        List<TripDtos.TripSearchResult> results =
                service.search(searcherId, request(wantedDeparture.toString(), 1, null));

        assertEquals(20, results.get(0).timeGapMin());
        assertEquals(20, results.get(1).timeGapMin());
        assertEquals(results.get(0).matchScore(), results.get(1).matchScore());
        // Equal scores fall back to the earlier departure.
        assertEquals(early.getId(), results.get(0).tripId());
    }

    // --- sorting ----------------------------------------------------------------------------

    @Test
    @DisplayName("best puts the highest score first")
    void bestSortsByScore() {
        // 800 m costs 14 of the 35 pickup points and 1600 m costs 28, so both scores are whole
        // numbers; a distance scoring exactly x.5 could round either way once measured.
        Trip near = perfectTrip();
        Trip mid = tripAt(latPlus(WANTED_ORIGIN_LAT, 800), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, "30.00", 4);
        Trip far = tripAt(latPlus(WANTED_ORIGIN_LAT, 1_600), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, "5.00", 4);
        givenCandidates(far, mid, near);

        List<TripDtos.TripSearchResult> results =
                service.search(searcherId, request(wantedDeparture.toString(), 1, "best"));

        assertEquals(List.of(near.getId(), mid.getId(), far.getId()),
                results.stream().map(TripDtos.TripSearchResult::tripId).toList());
        assertEquals(List.of(100, 86, 72),
                results.stream().map(TripDtos.TripSearchResult::matchScore).toList());
    }

    @Test
    @DisplayName("cheapest puts the lowest price first, even with a worse score")
    void cheapestSortsByPrice() {
        Trip cheapButFar = tripAt(latPlus(WANTED_ORIGIN_LAT, 1_600), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, "5.00", 4);
        Trip perfectButPricey = perfectTrip();
        givenCandidates(perfectButPricey, cheapButFar);

        List<TripDtos.TripSearchResult> results =
                service.search(searcherId, request(wantedDeparture.toString(), 1, "cheapest"));

        assertEquals(List.of(cheapButFar.getId(), perfectButPricey.getId()),
                results.stream().map(TripDtos.TripSearchResult::tripId).toList());
    }

    @Test
    @DisplayName("cheapest breaks a price tie with the better score")
    void cheapestBreaksTiesByScore() {
        Trip samePriceFar = tripAt(latPlus(WANTED_ORIGIN_LAT, 1_600), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, wantedDeparture, "12.00", 4);
        Trip samePricePerfect = perfectTrip();
        givenCandidates(samePriceFar, samePricePerfect);

        List<TripDtos.TripSearchResult> results =
                service.search(searcherId, request(wantedDeparture.toString(), 1, "cheapest"));

        assertEquals(samePricePerfect.getId(), results.get(0).tripId());
        assertEquals(samePriceFar.getId(), results.get(1).tripId());
    }

    @Test
    @DisplayName("earliest puts the soonest departure first, whatever it scores")
    void earliestSortsByDepartureTime() {
        Trip soonest = tripAt(latPlus(WANTED_ORIGIN_LAT, 1_600), WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG,
                wantedDeparture.minus(20, ChronoUnit.MINUTES), "30.00", 4);
        Trip onTime = perfectTrip();
        Trip latest = tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, wantedDeparture.plus(20, ChronoUnit.MINUTES), "5.00", 4);
        givenCandidates(latest, onTime, soonest);

        List<TripDtos.TripSearchResult> results =
                service.search(searcherId, request(wantedDeparture.toString(), 1, "earliest"));

        assertEquals(List.of(soonest.getId(), onTime.getId(), latest.getId()),
                results.stream().map(TripDtos.TripSearchResult::tripId).toList());
    }

    @Test
    @DisplayName("the sort parameter is read without regard to case or padding")
    void sortParameterIsNormalized() {
        givenCandidates(perfectTrip());

        assertEquals(1, service.search(searcherId, request(wantedDeparture.toString(), 1, "  CHEAPEST  ")).size());
    }

    @Test
    @DisplayName("at most fifty results come back")
    void capsResultsAtFifty() {
        List<Trip> many = new ArrayList<>();
        for (int i = 0; i < 60; i++) {
            many.add(perfectTrip());
        }
        givenCandidates(many.toArray(new Trip[0]));

        assertEquals(50, service.search(searcherId, request(wantedDeparture.toString(), 1, null)).size());
    }

    // --- helpers ----------------------------------------------------------------------------

    private TripDtos.SearchRequest request(String departureTime, Integer seats, String sort) {
        return new TripDtos.SearchRequest(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG,
                WANTED_DESTINATION_LAT, WANTED_DESTINATION_LNG, departureTime, seats, sort);
    }

    private Trip perfectTrip() {
        return tripAt(WANTED_ORIGIN_LAT, WANTED_ORIGIN_LNG, WANTED_DESTINATION_LAT,
                WANTED_DESTINATION_LNG, wantedDeparture, "12.00", 4);
    }

    private Trip tripAt(double originLat, double originLng, double destinationLat,
            double destinationLng, Instant departure, String price, int seats) {
        return new Trip(otherDriver, null, "Origin", originLat, originLng, "Destination",
                destinationLat, destinationLng, departure, seats, new BigDecimal(price), false,
                null, null, null);
    }

    /** Moves a latitude north by an exact number of metres on the sphere GeoUtils measures with. */
    private static double latPlus(double latitude, double metres) {
        return latitude + metres * 180d / (Math.PI * GeoUtils.EARTH_RADIUS_M);
    }

    private void givenCandidates(Trip... candidates) {
        when(trips.searchCandidates(any(), any(), any(), any(), anyInt(), any(), anyDouble(),
                anyDouble(), anyDouble(), anyDouble(), anyDouble(), anyDouble(), anyDouble(),
                anyDouble())).thenReturn(List.of(candidates));
    }
}
