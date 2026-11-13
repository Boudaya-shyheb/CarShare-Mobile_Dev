package com.carshare.api.users;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import com.carshare.api.auth.AuthDtos;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class EffectiveStatusTest {
    private static AppUser user(UserStatus status, Instant until) {
        AppUser user = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        user.updateAccountStatus(status, until);
        return user;
    }

    @Test
    @DisplayName("an ended suspension or warning reads as ACTIVE with no end date, before the nightly job")
    void endedStatusReadsAsActive() {
        Instant ended = Instant.now().minus(1, ChronoUnit.MINUTES);
        for (UserStatus status : new UserStatus[] {UserStatus.SUSPENDED, UserStatus.WARNING}) {
            AppUser user = user(status, ended);

            assertEquals(UserStatus.ACTIVE, user.effectiveStatus(Instant.now()));
            assertNull(user.effectiveStatusUntil(Instant.now()));
            AuthDtos.UserProfile profile = AuthDtos.UserProfile.from(user);
            assertEquals("ACTIVE", profile.status());
            assertNull(profile.statusUntil());
            assertEquals("ACTIVE", AuthDtos.AdminUser.from(user).status());
        }
    }

    @Test
    @DisplayName("a suspension still running keeps its status and end date")
    void runningSuspensionIsUnchanged() {
        Instant until = Instant.now().plus(1, ChronoUnit.DAYS);
        AppUser user = user(UserStatus.SUSPENDED, until);

        assertEquals("SUSPENDED", AuthDtos.UserProfile.from(user).status());
        assertEquals(until, AuthDtos.UserProfile.from(user).statusUntil());
    }

    @Test
    @DisplayName("a ban never expires, whatever its date, and a warning with no end stays a warning")
    void bansAndOpenWarningsStay() {
        assertEquals(UserStatus.BANNED,
                user(UserStatus.BANNED, Instant.now().minus(5, ChronoUnit.DAYS)).effectiveStatus(Instant.now()));
        assertEquals(UserStatus.WARNING, user(UserStatus.WARNING, null).effectiveStatus(Instant.now()));
    }
}
