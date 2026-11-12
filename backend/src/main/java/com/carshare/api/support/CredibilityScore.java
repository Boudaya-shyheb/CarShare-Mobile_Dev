package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "credibility_scores")
public class CredibilityScore {
    public static final int INITIAL_SCORE = 100;

    @Id private UUID id;
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false, unique = true)
    private AppUser user;
    @Column(nullable = false) private short score = INITIAL_SCORE;
    @Column(name = "blocked_until") private Instant blockedUntil;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected CredibilityScore() { }

    public CredibilityScore(AppUser user) {
        this.id = UUID.randomUUID();
        this.user = user;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public void changeBy(int amount) {
        score = (short) Math.max(0, Math.min(100, score + amount));
    }

    public void blockUntil(Instant until) { blockedUntil = until; }

    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public int getScore() { return score; }
    public Instant getBlockedUntil() { return blockedUntil; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
