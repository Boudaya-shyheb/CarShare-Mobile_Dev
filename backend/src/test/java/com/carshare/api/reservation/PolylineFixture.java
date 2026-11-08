package com.carshare.api.reservation;

/**
 * Google's encoded polyline algorithm, so a test can state a route in plain coordinates and feed
 * it to {@link GeoUtils#decodePolyline}. Only the decoder ships; nothing in production encodes.
 */
final class PolylineFixture {
    private PolylineFixture() { }

    static String encode(double[][] points) {
        StringBuilder encoded = new StringBuilder();
        int lastLat = 0;
        int lastLng = 0;
        for (double[] point : points) {
            int lat = (int) Math.round(point[0] * 1e5);
            int lng = (int) Math.round(point[1] * 1e5);
            encodeValue(lat - lastLat, encoded);
            encodeValue(lng - lastLng, encoded);
            lastLat = lat;
            lastLng = lng;
        }
        return encoded.toString();
    }

    private static void encodeValue(int value, StringBuilder out) {
        int shifted = value < 0 ? ~(value << 1) : value << 1;
        while (shifted >= 0x20) {
            out.append((char) ((0x20 | (shifted & 0x1f)) + 63));
            shifted >>= 5;
        }
        out.append((char) (shifted + 63));
    }
}
