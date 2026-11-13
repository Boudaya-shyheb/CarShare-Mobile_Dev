package com.carshare.api.users;

import com.carshare.api.common.ApiException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;

/**
 * The one place that decides whether an account may make changes.
 *
 * <ul>
 *   <li>{@code BANNED}: refused everywhere, sign-in included ({@code account_banned}).</li>
 *   <li>{@code SUSPENDED}: may sign in and look around; every write is refused
 *       ({@code account_suspended}, with {@code statusUntil}) while the suspension lasts.</li>
 *   <li>{@code WARNING} and {@code ACTIVE}: no restriction.</li>
 * </ul>
 *
 * <p>{@code statusUntil} is read live: a suspension whose end has passed no longer blocks, even
 * before the nightly job has cleaned the status up. Every module calls this instead of looking
 * at {@code getAccountStatus()} itself, so the rule cannot drift between them.
 *
 * <p>Deliberately not applied to the actions that let a restricted user tidy up after
 * themselves (cancelling their own reservation or trip, closing a handover, withdrawing a
 * ticket, signing out): refusing those would strand the other people involved.
 */
public final class ActiveUserGuard {
    private static final DateTimeFormatter WHEN =
            DateTimeFormatter.ofPattern("d MMM uuuu 'at' HH:mm 'UTC'", Locale.ENGLISH)
                    .withZone(ZoneOffset.UTC);

    private ActiveUserGuard() { }

    /** Loads the user and refuses a banned or currently suspended one. */
    public static AppUser requireActive(UserRepository users, UUID userId) {
        return requireActive(users, userId, Instant.now());
    }

    public static AppUser requireActive(UserRepository users, UUID userId, Instant now) {
        AppUser user = users.findById(userId).orElseThrow(() -> new ApiException(
                HttpStatus.UNAUTHORIZED, "account_not_found", "Your account could not be found."));
        check(user, now);
        return user;
    }

    /** Refuses a banned user, and a suspended one whose suspension has not ended. */
    public static void check(AppUser user, Instant now) {
        if (user.getAccountStatus() == UserStatus.BANNED) {
            throw banned();
        }
        if (isSuspendedAt(user, now)) {
            Instant until = user.getStatusUntil();
            String message = until == null
                    ? "Your account is suspended, so you cannot make changes. Contact CarShare support."
                    : "Your account is suspended until " + WHEN.format(until)
                            + ", so you cannot make changes. You can still sign in and look around.";
            throw new ApiException(HttpStatus.FORBIDDEN, "account_suspended", message,
                    until == null ? Map.of() : Map.of("statusUntil", until.toString()));
        }
    }

    /** Sign-in is refused only for a banned account; a suspended user may sign in. */
    public static void checkCanSignIn(AppUser user) {
        if (user.getAccountStatus() == UserStatus.BANNED) {
            throw banned();
        }
    }

    /** True while the user is suspended: no end date, or an end date still ahead. */
    public static boolean isSuspendedAt(AppUser user, Instant now) {
        return user.getAccountStatus() == UserStatus.SUSPENDED
                && (user.getStatusUntil() == null || user.getStatusUntil().isAfter(now));
    }

    private static ApiException banned() {
        return new ApiException(HttpStatus.FORBIDDEN, "account_banned",
                "Your account has been banned, so you can no longer use CarShare. "
                        + "Contact CarShare support if you think this is a mistake.");
    }
}
