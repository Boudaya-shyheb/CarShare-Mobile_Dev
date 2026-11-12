package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "support_agent_profiles")
public class SupportAgentProfile {
    @Id @Column(name = "user_id") private java.util.UUID userId;
    @MapsId @OneToOne(fetch = FetchType.LAZY) @JoinColumn(name = "user_id") private AppUser user;
    @Column(nullable = false) private boolean available = true;
    @Column(nullable = false, length = 500) private String skills = "GENERAL";
    @Column(nullable = false) private int capacity = 10;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected SupportAgentProfile() { }
    public SupportAgentProfile(AppUser user) {
        this.user = user; userId = user.getId(); updatedAt = Instant.now();
    }
    public void update(boolean available, String skills, int capacity) {
        this.available = available; this.skills = skills; this.capacity = capacity;
        updatedAt = Instant.now();
    }
    public AppUser getUser() { return user; }
    public boolean isAvailable() { return available; }
    public String getSkills() { return skills; }
    public int getCapacity() { return capacity; }
}
