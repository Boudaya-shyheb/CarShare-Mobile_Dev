package com.carshare.api.lostandfound;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "lost_and_found_notifications")
public class LostAndFoundNotification {

    public enum Type {
        MATCH_FOUND, MATCH_CONFIRMED, MEETING_ARRANGED, ITEM_RETURNED, NOT_MY_ITEM
    }

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 24)
    private Type type;

    @Column(name = "report_id")
    private UUID reportId;

    @Column(name = "handover_id")
    private UUID handoverId;

    @Column(nullable = false, length = 120)
    private String title;

    @Column(nullable = false, length = 400)
    private String body;

    @Column(name = "read_at")
    private Instant readAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected LostAndFoundNotification() {
    }

    public LostAndFoundNotification(AppUser user, Type type, UUID reportId, UUID handoverId,
            String title, String body) {
        this.id = UUID.randomUUID();
        this.user = user;
        this.type = type;
        this.reportId = reportId;
        this.handoverId = handoverId;
        this.title = title.length() > 120 ? title.substring(0, 120) : title;
        this.body = body.length() > 400 ? body.substring(0, 400) : body;
        this.createdAt = Instant.now();
    }

    public void markRead(Instant now) {
        if (readAt == null) readAt = now;
    }

    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public Type getType() { return type; }
    public UUID getReportId() { return reportId; }
    public UUID getHandoverId() { return handoverId; }
    public String getTitle() { return title; }
    public String getBody() { return body; }
    public Instant getReadAt() { return readAt; }
    public Instant getCreatedAt() { return createdAt; }
}
