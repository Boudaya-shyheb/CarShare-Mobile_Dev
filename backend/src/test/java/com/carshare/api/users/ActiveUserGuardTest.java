package com.carshare.api.users;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ActiveUserGuardTest {
    private static final Instant NOW = Instant.parse("2026-11-12T12:00:00Z");

    private static AppUser user(UserStatus status, Instant until) {
        AppUser user = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        user.updateAccountStatus(status, until);
        return user;
    }

    @Test
    @DisplayName("a banned user is refused with account_banned")
    void bannedIsRefused() {
        ApiException error = assertThrows(ApiException.class,
                () -> ActiveUserGuard.check(user(UserStatus.BANNED, null), NOW));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("account_banned", error.getCode());
    }

    @Test
    @DisplayName("a banned user stays refused whatever statusUntil says")
    void bannedIgnoresTheEndDate() {
        AppUser banned = user(UserStatus.BANNED, NOW.minus(1, ChronoUnit.DAYS));

        assertEquals("account_banned",
                assertThrows(ApiException.class, () -> ActiveUserGuard.check(banned, NOW)).getCode());
    }

    @Test
    @DisplayName("a suspended user is refused with account_suspended and the end date")
    void suspendedIsRefusedWithTheEndDate() {
        Instant until = NOW.plus(1, ChronoUnit.DAYS);

        ApiException error = assertThrows(ApiException.class,
                () -> ActiveUserGuard.check(user(UserStatus.SUSPENDED, until), NOW));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        assertEquals("account_suspended", error.getCode());
        assertEquals(until.toString(), error.getProperties().get("statusUntil"));
        assertTrue(error.getMessage().contains("13 Nov 2026 at 12:00 UTC"), error.getMessage());
    }

    @Test
    @DisplayName("a suspension with no end date blocks and carries no statusUntil")
    void openEndedSuspensionBlocks() {
        ApiException error = assertThrows(ApiException.class,
                () -> ActiveUserGuard.check(user(UserStatus.SUSPENDED, null), NOW));

        assertEquals("account_suspended", error.getCode());
        assertFalse(error.getProperties().containsKey("statusUntil"));
    }

    @Test
    @DisplayName("an expired suspension no longer blocks, even before the nightly job has run")
    void expiredSuspensionIsLive() {
        AppUser expired = user(UserStatus.SUSPENDED, NOW.minus(1, ChronoUnit.MINUTES));

        assertDoesNotThrow(() -> ActiveUserGuard.check(expired, NOW));
        assertFalse(ActiveUserGuard.isSuspendedAt(expired, NOW));
    }

    @Test
    @DisplayName("a warning and an active account are never blocked")
    void warningDoesNotBlock() {
        assertDoesNotThrow(() -> ActiveUserGuard.check(user(UserStatus.WARNING, null), NOW));
        assertDoesNotThrow(() -> ActiveUserGuard.check(user(UserStatus.ACTIVE, null), NOW));
    }

    @Test
    @DisplayName("signing in is refused only for a banned account")
    void signInIsRefusedOnlyWhenBanned() {
        assertEquals("account_banned", assertThrows(ApiException.class,
                () -> ActiveUserGuard.checkCanSignIn(user(UserStatus.BANNED, null))).getCode());
        assertDoesNotThrow(() -> ActiveUserGuard.checkCanSignIn(
                user(UserStatus.SUSPENDED, NOW.plus(2, ChronoUnit.DAYS))));
        assertDoesNotThrow(() -> ActiveUserGuard.checkCanSignIn(user(UserStatus.WARNING, null)));
    }

    @Test
    @DisplayName("requireActive loads the user, returns it, and answers 401 for an unknown one")
    void requireActiveLoadsTheUser() {
        UserRepository users = mock(UserRepository.class);
        AppUser fine = user(UserStatus.ACTIVE, null);
        when(users.findById(fine.getId())).thenReturn(Optional.of(fine));
        UUID unknown = UUID.randomUUID();
        when(users.findById(unknown)).thenReturn(Optional.empty());

        assertSame(fine, ActiveUserGuard.requireActive(users, fine.getId(), NOW));
        ApiException error = assertThrows(ApiException.class,
                () -> ActiveUserGuard.requireActive(users, unknown, NOW));
        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals("account_not_found", error.getCode());
        assertNull(error.getProperties().get("statusUntil"));
    }
}
