package com.carshare.api.lostandfound;

import com.carshare.api.security.SessionPrincipal;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The caller's Lost & Found notifications. Reading and marking as read are open to a suspended
 * user, like Support notifications: they only touch the user's own inbox.
 */
@RestController
@RequestMapping("/api/lost-and-found/notifications")
public class LostAndFoundNotificationController {
    private final LostAndFoundNotificationService service;

    public LostAndFoundNotificationController(LostAndFoundNotificationService service) {
        this.service = service;
    }

    @GetMapping
    public List<LostAndFoundNotificationService.NotificationView> mine(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return service.mine(principal.userId());
    }

    @GetMapping("/unread-count")
    public LostAndFoundNotificationService.UnreadCount unreadCount(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return service.unreadCount(principal.userId());
    }

    @PostMapping("/{notificationId}/read")
    public LostAndFoundNotificationService.NotificationView markRead(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID notificationId) {
        return service.markRead(principal.userId(), notificationId);
    }

    @PostMapping("/read-all")
    public LostAndFoundNotificationService.UnreadCount markAllRead(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return service.markAllRead(principal.userId());
    }
}
