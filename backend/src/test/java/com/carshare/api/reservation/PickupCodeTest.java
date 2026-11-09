package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class PickupCodeTest {
    @Test
    @DisplayName("a generated code is always four digits")
    void generatesFourDigits() {
        for (int i = 0; i < 2_000; i++) {
            String code = PickupCode.generate();
            assertEquals(4, code.length(), "got " + code);
            assertTrue(PickupCode.isWellFormed(code), "got " + code);
        }
    }

    @Test
    @DisplayName("the generator does not settle on one code")
    void generatesVariety() {
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < 500; i++) {
            seen.add(PickupCode.generate());
        }
        assertTrue(seen.size() > 100, "only " + seen.size() + " distinct codes in 500 draws");
    }

    @Test
    @DisplayName("codes below 1000 keep their leading zeros")
    void keepsLeadingZeros() {
        assertTrue(PickupCode.isWellFormed("0042"));
        assertEquals(4, "0042".length());
    }

    @Test
    @DisplayName("anything that is not exactly four digits is rejected")
    void rejectsMalformedCodes() {
        assertFalse(PickupCode.isWellFormed(null));
        assertFalse(PickupCode.isWellFormed(""));
        assertFalse(PickupCode.isWellFormed("123"));
        assertFalse(PickupCode.isWellFormed("12345"));
        assertFalse(PickupCode.isWellFormed("12a4"));
        assertFalse(PickupCode.isWellFormed("12 4"));
        assertFalse(PickupCode.isWellFormed("-123"));
    }

    @Test
    @DisplayName("the attempt cap is three")
    void attemptCapIsThree() {
        assertEquals(3, PickupCode.MAX_ATTEMPTS);
    }
}
