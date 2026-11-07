package com.carshare.api.reservation;

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
}
