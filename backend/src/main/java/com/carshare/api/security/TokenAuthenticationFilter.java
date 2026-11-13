package com.carshare.api.security;

import com.carshare.api.auth.AuthSessionRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.carshare.api.users.UserStatus;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.time.Instant;
import java.util.List;

public class TokenAuthenticationFilter extends OncePerRequestFilter {
    private final AuthSessionRepository sessions;

    public TokenAuthenticationFilter(AuthSessionRepository sessions) {
        this.sessions = sessions;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7).trim();
            if (!token.isEmpty()) {
                String tokenHash = TokenUtil.sha256(token);
                var found = sessions.findByTokenHashAndExpiresAtAfter(tokenHash, Instant.now());
                if (found.isPresent() && found.get().getUser().getAccountStatus() == UserStatus.BANNED
                        && !request.getRequestURI().endsWith("/auth/signout")) {
                    refuseBanned(response);
                    return;
                }
                found.ifPresent(session -> {
                    var user = session.getUser();
                    var principal = new SessionPrincipal(user.getId(), tokenHash);
                    var authentication = new UsernamePasswordAuthenticationToken(principal, null,
                            List.of(new SimpleGrantedAuthority("ROLE_" + user.getRole().name())));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                });
            }
        }
        chain.doFilter(request, response);
    }

    /** A banned account is refused everywhere with the same code the sign-in uses. */
    private static void refuseBanned(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/problem+json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"status\":403,\"code\":\"account_banned\",\"detail\":"
                + "\"Your account has been banned, so you can no longer use CarShare. "
                + "Contact CarShare support if you think this is a mistake.\"}");
    }
}
