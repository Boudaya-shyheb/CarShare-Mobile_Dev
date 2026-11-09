package com.carshare.api.reservation;

import java.util.ArrayList;
import java.util.List;

/**
 * Spherical distance helpers shared by trip search, the pickup and drop-off geofences, and the
 * route deviation alert.
 */
public final class GeoUtils {
    public static final double EARTH_RADIUS_M = 6_371_000d;

    /**
     * One degree of latitude on the sphere this class measures with. Derived from the same radius
     * as the haversine so a bounding box never cuts off a point the haversine would have kept.
     */
    private static final double METRES_PER_DEGREE_LATITUDE = Math.PI * EARTH_RADIUS_M / 180d;

    /** Widens the bounding box slightly, so rounding can never shrink it inside the radius. */
    private static final double BOX_SAFETY_MARGIN = 1.001d;

    /** Google encoded polylines carry five decimal places. */
    private static final double POLYLINE_PRECISION = 1e5;

    private GeoUtils() { }

    /** Great-circle distance in metres between two WGS-84 points. */
    public static double haversineMetres(double lat1, double lng1, double lat2, double lng2) {
        double halfLatDelta = Math.sin(Math.toRadians(lat2 - lat1) / 2);
        double halfLngDelta = Math.sin(Math.toRadians(lng2 - lng1) / 2);
        double a = halfLatDelta * halfLatDelta
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                        * halfLngDelta * halfLngDelta;
        return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1d, Math.sqrt(a)));
    }

    /** Degrees of latitude covering the given radius; used for the SQL bounding box. */
    public static double latitudeDelta(double radiusMetres) {
        return BOX_SAFETY_MARGIN * radiusMetres / METRES_PER_DEGREE_LATITUDE;
    }

    /**
     * Degrees of longitude covering the given radius at a latitude. Meridians converge towards the
     * poles, so the same distance spans more degrees the further north or south you are.
     */
    public static double longitudeDelta(double radiusMetres, double atLatitude) {
        double convergence = Math.cos(Math.toRadians(atLatitude));
        if (convergence < 1e-6) {
            return 180d; // At the poles every longitude is within the radius.
        }
        return Math.min(180d, latitudeDelta(radiusMetres) / convergence);
    }

    /**
     * Decodes a Google encoded polyline into {lat, lng} pairs.
     *
     * <p>Tolerant by design: the string comes from the phone, and a truncated or corrupt one
     * yields the points decoded so far rather than an exception, so a bad polyline costs the trip
     * its deviation alert and nothing else.
     */
    public static List<double[]> decodePolyline(String encoded) {
        if (encoded == null || encoded.isBlank()) {
            return List.of();
        }
        List<double[]> points = new ArrayList<>();
        int index = 0;
        int lat = 0;
        int lng = 0;
        while (index < encoded.length()) {
            Decoded latitude = decodeValue(encoded, index);
            if (latitude == null) break;
            Decoded longitude = decodeValue(encoded, latitude.nextIndex());
            if (longitude == null) break;
            lat += latitude.value();
            lng += longitude.value();
            index = longitude.nextIndex();
            points.add(new double[] { lat / POLYLINE_PRECISION, lng / POLYLINE_PRECISION });
        }
        return List.copyOf(points);
    }

    /**
     * Shortest distance in metres from a point to a decoded polyline, measured against its
     * segments rather than only its vertices.
     *
     * @return {@code Double.NaN} when the polyline holds no points, which the caller must treat
     *         as "no route to compare against" rather than as a distance
     */
    public static double distanceToPolylineMetres(double lat, double lng, List<double[]> polyline) {
        if (polyline == null || polyline.isEmpty()) {
            return Double.NaN;
        }
        if (polyline.size() == 1) {
            return haversineMetres(lat, lng, polyline.get(0)[0], polyline.get(0)[1]);
        }
        double shortest = Double.MAX_VALUE;
        for (int i = 1; i < polyline.size(); i++) {
            double[] from = polyline.get(i - 1);
            double[] to = polyline.get(i);
            shortest = Math.min(shortest,
                    distanceToSegmentMetres(lat, lng, from[0], from[1], to[0], to[1]));
        }
        return shortest;
    }

    /**
     * Distance in metres from a point to the line segment between two points, including the
     * segment's interior.
     *
     * <p>Projects the three points onto a flat plane centred on the point being measured. Over
     * the few hundred metres this is used for, the error against a proper great-circle
     * cross-track distance is far below the accuracy of a phone's GPS.
     */
    public static double distanceToSegmentMetres(double lat, double lng,
            double fromLat, double fromLng, double toLat, double toLng) {
        double metresPerDegreeLng = METRES_PER_DEGREE_LATITUDE * Math.cos(Math.toRadians(lat));
        double fromX = (fromLng - lng) * metresPerDegreeLng;
        double fromY = (fromLat - lat) * METRES_PER_DEGREE_LATITUDE;
        double toX = (toLng - lng) * metresPerDegreeLng;
        double toY = (toLat - lat) * METRES_PER_DEGREE_LATITUDE;

        double runX = toX - fromX;
        double runY = toY - fromY;
        double lengthSquared = runX * runX + runY * runY;
        if (lengthSquared == 0d) {
            return Math.hypot(fromX, fromY); // The segment is a single point.
        }
        // How far along the segment the closest point sits, clamped to the segment itself.
        double along = Math.max(0d, Math.min(1d, -(fromX * runX + fromY * runY) / lengthSquared));
        return Math.hypot(fromX + along * runX, fromY + along * runY);
    }

    private static Decoded decodeValue(String encoded, int start) {
        int result = 0;
        int shift = 0;
        int index = start;
        while (index < encoded.length()) {
            int chunk = encoded.charAt(index++) - 63;
            if (chunk < 0) {
                return null; // Not a polyline character.
            }
            result |= (chunk & 0x1f) << shift;
            if (chunk < 0x20) {
                return new Decoded((result & 1) != 0 ? ~(result >> 1) : result >> 1, index);
            }
            shift += 5;
            if (shift > 30) {
                return null; // Malformed: the value would overflow.
            }
        }
        return null; // Ran out of characters part-way through a value.
    }

    private record Decoded(int value, int nextIndex) { }
}
