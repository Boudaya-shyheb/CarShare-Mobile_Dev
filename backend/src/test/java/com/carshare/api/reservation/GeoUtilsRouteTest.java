package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** Polyline decoding and point-to-segment distance, which the deviation alert is built on. */
class GeoUtilsRouteTest {
    /** The example from Google's own encoded polyline documentation. */
    private static final String GOOGLE_EXAMPLE = "_p~iF~ps|U_ulLnnqC_mqNvxq`@";

    private static final double ROUTE_LAT = 36.80;

    @Test
    @DisplayName("the documented Google example decodes to its three published points")
    void decodesTheDocumentedExample() {
        List<double[]> points = GeoUtils.decodePolyline(GOOGLE_EXAMPLE);

        assertEquals(3, points.size());
        assertEquals(38.5, points.get(0)[0], 1e-9);
        assertEquals(-120.2, points.get(0)[1], 1e-9);
        assertEquals(40.7, points.get(1)[0], 1e-9);
        assertEquals(-120.95, points.get(1)[1], 1e-9);
        assertEquals(43.252, points.get(2)[0], 1e-9);
        assertEquals(-126.453, points.get(2)[1], 1e-9);
    }

    @Test
    @DisplayName("an absent or empty polyline decodes to nothing")
    void decodesNothingFromNothing() {
        assertTrue(GeoUtils.decodePolyline(null).isEmpty());
        assertTrue(GeoUtils.decodePolyline("").isEmpty());
        assertTrue(GeoUtils.decodePolyline("   ").isEmpty());
    }

    @Test
    @DisplayName("a truncated polyline yields the points it managed to decode")
    void decodesWhatItCanFromATruncatedPolyline() {
        // Two whole points followed by half of a third.
        String truncated = GOOGLE_EXAMPLE.substring(0, GOOGLE_EXAMPLE.length() - 3);

        List<double[]> points = GeoUtils.decodePolyline(truncated);

        assertEquals(2, points.size());
        assertEquals(38.5, points.get(0)[0], 1e-9);
        assertEquals(40.7, points.get(1)[0], 1e-9);
    }

    @Test
    @DisplayName("junk decodes to nothing instead of throwing")
    void survivesJunk() {
        assertTrue(GeoUtils.decodePolyline("!!!").isEmpty());
        assertEquals(0, GeoUtils.decodePolyline(" ~~~ ").size());
    }

    @Test
    @DisplayName("the decoder round-trips a polyline built by the documented algorithm")
    void roundTripsAnEncodedRoute() {
        double[][] route = { { 36.8065, 10.1815 }, { 36.75, 10.25 }, { 35.8256, 10.6360 } };

        List<double[]> decoded = GeoUtils.decodePolyline(PolylineFixture.encode(route));

        assertEquals(route.length, decoded.size());
        for (int i = 0; i < route.length; i++) {
            assertEquals(route[i][0], decoded.get(i)[0], 1e-5);
            assertEquals(route[i][1], decoded.get(i)[1], 1e-5);
        }
    }

    @Test
    @DisplayName("a point on the segment is on the segment")
    void measuresZeroOnTheSegment() {
        double metres = GeoUtils.distanceToSegmentMetres(ROUTE_LAT, 10.19,
                ROUTE_LAT, 10.18, ROUTE_LAT, 10.20);

        assertEquals(0d, metres, 0.5);
    }

    @Test
    @DisplayName("a point beside the middle of a segment measures the perpendicular distance")
    void measuresPerpendicularDistance() {
        double metres = GeoUtils.distanceToSegmentMetres(latPlus(ROUTE_LAT, 400), 10.19,
                ROUTE_LAT, 10.18, ROUTE_LAT, 10.20);

        assertEquals(400d, metres, 2d);
    }

    @Test
    @DisplayName("a point past the end of a segment measures to that end, not to the line")
    void measuresToTheNearestEnd() {
        // Due east of the segment's eastern end, so the foot of the perpendicular is off the end.
        double metres = GeoUtils.distanceToSegmentMetres(ROUTE_LAT, 10.25,
                ROUTE_LAT, 10.18, ROUTE_LAT, 10.20);
        double toTheEnd = GeoUtils.haversineMetres(ROUTE_LAT, 10.25, ROUTE_LAT, 10.20);

        assertEquals(toTheEnd, metres, 2d);
    }

    @Test
    @DisplayName("a segment with no length measures like a plain distance")
    void handlesADegenerateSegment() {
        double metres = GeoUtils.distanceToSegmentMetres(latPlus(ROUTE_LAT, 250), 10.18,
                ROUTE_LAT, 10.18, ROUTE_LAT, 10.18);

        assertEquals(250d, metres, 2d);
    }

    @Test
    @DisplayName("the polyline distance measures against segments, not only vertices")
    void measuresAgainstTheSegmentNotTheVertices() {
        // A long leg with its vertices far away; the point sits beside its middle.
        List<double[]> route = GeoUtils.decodePolyline(
                PolylineFixture.encode(new double[][] { { ROUTE_LAT, 10.10 }, { ROUTE_LAT, 10.30 } }));
        double lat = latPlus(ROUTE_LAT, 300);

        double toRoute = GeoUtils.distanceToPolylineMetres(lat, 10.20, route);
        double toNearestVertex = Math.min(
                GeoUtils.haversineMetres(lat, 10.20, ROUTE_LAT, 10.10),
                GeoUtils.haversineMetres(lat, 10.20, ROUTE_LAT, 10.30));

        assertEquals(300d, toRoute, 3d);
        assertTrue(toNearestVertex > 8_000, "the vertices should be far away: " + toNearestVertex);
    }

    @Test
    @DisplayName("the polyline distance takes the closest of several legs")
    void takesTheClosestLeg() {
        List<double[]> route = GeoUtils.decodePolyline(PolylineFixture.encode(new double[][] {
                { ROUTE_LAT, 10.10 }, { ROUTE_LAT, 10.20 }, { latPlus(ROUTE_LAT, 5_000), 10.20 } }));

        // Beside the first leg, and far from the second.
        assertEquals(150d,
                GeoUtils.distanceToPolylineMetres(latPlus(ROUTE_LAT, 150), 10.15, route), 3d);
        // Beside the second leg, and far from the first.
        assertEquals(150d, GeoUtils.distanceToPolylineMetres(latPlus(ROUTE_LAT, 2_500),
                lngPlus(10.20, 150, ROUTE_LAT), route), 5d);
    }

    @Test
    @DisplayName("a one-point route is measured as a plain distance")
    void handlesASinglePointRoute() {
        List<double[]> route = GeoUtils.decodePolyline(PolylineFixture.encode(new double[][] { { ROUTE_LAT, 10.18 } }));

        assertEquals(1, route.size());
        assertEquals(400d,
                GeoUtils.distanceToPolylineMetres(latPlus(ROUTE_LAT, 400), 10.18, route), 2d);
    }

    @Test
    @DisplayName("an empty route gives no distance at all, rather than zero")
    void reportsNoDistanceForAnEmptyRoute() {
        assertTrue(Double.isNaN(GeoUtils.distanceToPolylineMetres(ROUTE_LAT, 10.18, List.of())));
        assertTrue(Double.isNaN(GeoUtils.distanceToPolylineMetres(ROUTE_LAT, 10.18, null)));
    }

    // --- helpers ----------------------------------------------------------------------------

    private static double latPlus(double latitude, double metres) {
        return latitude + metres * 180d / (Math.PI * GeoUtils.EARTH_RADIUS_M);
    }

    private static double lngPlus(double longitude, double metres, double atLatitude) {
        return longitude + metres * 180d
                / (Math.PI * GeoUtils.EARTH_RADIUS_M * Math.cos(Math.toRadians(atLatitude)));
    }

}
