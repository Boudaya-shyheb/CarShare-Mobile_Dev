package com.carshare.api.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.UuidGenerator;

@Entity
@Table(name = "user_sanctions")
public class UserSanction {
    @Id
    @GeneratedValue
    @UuidGenerator
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;

    @Column(nullable = false)
    private int points;

    @Column(nullable = false, length = 500)
    private String reason;

    @Column(name = "issued_at", nullable = false)
    private Instant issuedAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    protected UserSanction() { }

    public UserSanction(AppUser user, int points, String reason) {
        this.user = user;
        this.points = points;
        this.reason = reason;
    }

    @PrePersist
    void setDates() {
        if (issuedAt == null) issuedAt = Instant.now();
        if (expiresAt == null) expiresAt = issuedAt.plusSeconds(90L * 24 * 60 * 60);
    }

    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public int getPoints() { return points; }
    public String getReason() { return reason; }
    public Instant getIssuedAt() { return issuedAt; }
    public Instant getExpiresAt() { return expiresAt; }
}
