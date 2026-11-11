package com.carshare.api.auth;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_auth_identities", uniqueConstraints = {
        @UniqueConstraint(name = "uq_user_auth_provider_subject", columnNames = {"provider", "provider_subject"}),
        @UniqueConstraint(name = "uq_user_auth_provider_user", columnNames = {"provider", "user_id"})
})
public class UserAuthIdentity {
    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;
    @Column(nullable = false, length = 16) private String provider;
    @Column(name = "provider_subject", nullable = false, length = 255) private String providerSubject;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected UserAuthIdentity() { }
    public UserAuthIdentity(AppUser user, String provider, String providerSubject) {
        id = UUID.randomUUID(); this.user = user; this.provider = provider;
        this.providerSubject = providerSubject; createdAt = Instant.now();
    }
    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public String getProvider() { return provider; }
    public String getProviderSubject() { return providerSubject; }
    public Instant getCreatedAt() { return createdAt; }
}
