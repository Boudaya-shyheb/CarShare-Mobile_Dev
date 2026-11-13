package com.carshare.api.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.auth.AuthSession;
import com.carshare.api.auth.AuthSessionRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import jakarta.servlet.FilterChain;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

class TokenAuthenticationFilterTest {
    private final AuthSessionRepository sessions = mock(AuthSessionRepository.class);
    private final FilterChain chain = mock(FilterChain.class);
    private final TokenAuthenticationFilter filter = new TokenAuthenticationFilter(sessions);

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    private MockHttpServletRequest requestFor(AppUser user, String path) {
        String token = "a-valid-token";
        AuthSession session = new AuthSession(user, TokenUtil.sha256(token), Instant.now().plus(1, ChronoUnit.DAYS));
        when(sessions.findByTokenHashAndExpiresAtAfter(eq(TokenUtil.sha256(token)), any()))
                .thenReturn(Optional.of(session));
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        request.addHeader("Authorization", "Bearer " + token);
        return request;
    }

    private AppUser user(UserStatus status) {
        AppUser user = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        user.updateAccountStatus(status, null);
        return user;
    }

    @Test
    @DisplayName("a banned user's token is refused with 403 account_banned on any route")
    void bannedTokenIsRefused() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(requestFor(user(UserStatus.BANNED), "/api/trips/mine"), response, chain);

        assertEquals(403, response.getStatus());
        assertTrue(response.getContentAsString().contains("\"code\":\"account_banned\""));
        verify(chain, never()).doFilter(any(), any());
        assertNull(SecurityContextHolder.getContext().getAuthentication());
    }

    @Test
    @DisplayName("a banned user can still sign out")
    void bannedUserCanSignOut() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(requestFor(user(UserStatus.BANNED), "/api/auth/signout"), response, chain);

        verify(chain).doFilter(any(), any());
        assertNotNull(SecurityContextHolder.getContext().getAuthentication());
    }

    @Test
    @DisplayName("a suspended user is authenticated: they can sign in and look around")
    void suspendedUserIsAuthenticated() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(requestFor(user(UserStatus.SUSPENDED), "/api/trips/mine"), response, chain);

        assertEquals(200, response.getStatus());
        verify(chain).doFilter(any(), any());
        assertNotNull(SecurityContextHolder.getContext().getAuthentication());
    }
}
