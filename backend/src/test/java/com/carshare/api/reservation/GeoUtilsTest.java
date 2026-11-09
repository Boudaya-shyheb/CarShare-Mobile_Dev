package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class GeoUtilsTest {
    private static final double TUNIS_LAT = 36.8065;
    private static final double TUNIS_LNG = 10.1815;
    private static final double SOUSSE_LAT = 35.8256;
    private static final double SOUSSE_LNG = 10.6360;

    @Test
    @DisplayName("Tunis Centre to Sousse is about 116 km in a straight line")
    void measuresTunisToSousse() {
        double metres = GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, SOUSSE_LAT, SOUSSE_LNG);

        assertTrue(metres > 115_000 && metres < 120_000,
                "expected 115-120 km, measured " + Math.round(metres) + " m");
    }

    @Test
    @DisplayName("the distance from a point to itself is zero")
    void measuresZeroForTheSamePoint() {
        assertEquals(0d, GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, TUNIS_LAT, TUNIS_LNG), 0.001);
    }

    @Test
    @DisplayName("the distance is the same in both directions")
    void isSymmetric() {
        assertEquals(GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, SOUSSE_LAT, SOUSSE_LNG),
                GeoUtils.haversineMetres(SOUSSE_LAT, SOUSSE_LNG, TUNIS_LAT, TUNIS_LNG), 0.001);
    }

    @Test
    @DisplayName("one degree of latitude is about 111 km anywhere")
    void measuresOneDegreeOfLatitude() {
        double atEquator = GeoUtils.haversineMetres(0, 0, 1, 0);
        double inTunisia = GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, TUNIS_LAT + 1, TUNIS_LNG);

        assertTrue(atEquator > 111_000 && atEquator < 111_400, "measured " + atEquator);
        assertEquals(atEquator, inTunisia, 1d);
    }

    @Test
    @DisplayName("a hundredth of a degree of latitude is a little over a kilometre")
    void measuresShortDistance() {
        double metres = GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, TUNIS_LAT + 0.01, TUNIS_LNG);

        assertTrue(metres > 1_100 && metres < 1_125, "measured " + Math.round(metres) + " m");
    }

    @Test
    @DisplayName("a degree of longitude shrinks towards the poles, so the box grows")
    void longitudeDeltaGrowsWithLatitude() {
        double atEquator = GeoUtils.longitudeDelta(2_000, 0);
        double inTunisia = GeoUtils.longitudeDelta(2_000, TUNIS_LAT);
        double inNorway = GeoUtils.longitudeDelta(2_000, 69.65);

        assertEquals(GeoUtils.latitudeDelta(2_000), atEquator, 1e-9);
        assertTrue(inTunisia > atEquator, "Tunisia " + inTunisia + " vs equator " + atEquator);
        assertTrue(inNorway > inTunisia, "Norway " + inNorway + " vs Tunisia " + inTunisia);
    }

    @Test
    @DisplayName("the bounding box for two kilometres is about 0.018 degrees of latitude")
    void latitudeDeltaForTwoKilometres() {
        assertEquals(0.01797, GeoUtils.latitudeDelta(2_000), 0.0001);
    }

    @Test
    @DisplayName("at the poles every longitude is inside the radius")
    void longitudeDeltaIsClampedAtThePoles() {
        assertEquals(180d, GeoUtils.longitudeDelta(2_000, 90));
        assertEquals(180d, GeoUtils.longitudeDelta(2_000, -90));
    }

    @Test
    @DisplayName("the bounding box always covers the exact distance it approximates")
    void boundingBoxCoversTheRadius() {
        // A point exactly at the edge of the box must be at least the radius away, otherwise the
        // SQL pre-filter would drop trips the haversine check would have kept.
        double latDelta = GeoUtils.latitudeDelta(2_000);
        double lngDelta = GeoUtils.longitudeDelta(2_000, TUNIS_LAT);

        assertTrue(GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, TUNIS_LAT + latDelta, TUNIS_LNG)
                >= 2_000);
        assertTrue(GeoUtils.haversineMetres(TUNIS_LAT, TUNIS_LNG, TUNIS_LAT, TUNIS_LNG + lngDelta)
                >= 2_000);
    }
}
