package com.carshare.api.reservation;

import java.security.SecureRandom;

/**
 * The 4-digit code a passenger shows at pickup. The driver types it in to move the trip from
 * DRIVER_ARRIVED to PICKED_UP (step 6).
 */
public final class PickupCode {
    public static final int LENGTH = 4;

    /** Wrong codes allowed before check-in is locked; enforced by the service, not the schema. */
    public static final int MAX_ATTEMPTS = 3;

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int UPPER_BOUND = 10_000;

    private PickupCode() { }

    /** A uniformly random code from 0000 to 9999, keeping the leading zeros. */
    public static String generate() {
        return String.format("%04d", RANDOM.nextInt(UPPER_BOUND));
    }

    public static boolean isWellFormed(String code) {
        if (code == null || code.length() != LENGTH) {
            return false;
        }
        for (int i = 0; i < LENGTH; i++) {
            if (code.charAt(i) < '0' || code.charAt(i) > '9') {
                return false;
            }
        }
        return true;
    }
}
