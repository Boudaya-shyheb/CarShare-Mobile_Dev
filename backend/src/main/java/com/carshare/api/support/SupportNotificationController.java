package com.carshare.api.support;

import com.carshare.api.security.SessionPrincipal;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/support/notifications")
public class SupportNotificationController {
    private final SupportService support;

    public SupportNotificationController(SupportService support) {
        this.support = support;
    }

    @GetMapping
    public List<SupportService.NotificationView> notifications(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return support.notifications(principal.userId());
    }

    @GetMapping("/unread-count")
    public SupportService.UnreadCount unreadCount(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return support.unreadCount(principal.userId());
    }

    @PutMapping("/{notificationId}/read")
    public SupportService.NotificationView markRead(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID notificationId) {
        return support.markNotificationRead(principal.userId(), notificationId);
    }
}
