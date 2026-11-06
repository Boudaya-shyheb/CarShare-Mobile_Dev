package com.carshare.api.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "user_preferences")
public class UserPreferences {
    @Id
    @Column(name = "user_id")
    private UUID userId;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @MapsId
    @JoinColumn(name = "user_id")
    private AppUser user;

    @Column(nullable = false, length = 10)
    private String language = "en";

    @Column(name = "home_place", length = 180)
    private String homePlace;

    @Column(name = "work_place", length = 180)
    private String workPlace;

    @Column(name = "campus_place", length = 180)
    private String campusPlace;

    @Column(name = "music_allowed", nullable = false)
    private boolean musicAllowed = true;

    @Column(name = "smoking_allowed", nullable = false)
    private boolean smokingAllowed;

    @Column(name = "pets_allowed", nullable = false)
    private boolean petsAllowed;

    @Column(name = "luggage_preference", nullable = false, length = 20)
    private String luggagePreference = "standard";

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected UserPreferences() { }

    public UserPreferences(AppUser user) {
        this.user = user;
    }

    public void update(String language, String homePlace, String workPlace, String campusPlace,
            boolean musicAllowed, boolean smokingAllowed, boolean petsAllowed, String luggagePreference) {
        this.language = language;
        this.homePlace = homePlace;
        this.workPlace = workPlace;
        this.campusPlace = campusPlace;
        this.musicAllowed = musicAllowed;
        this.smokingAllowed = smokingAllowed;
        this.petsAllowed = petsAllowed;
        this.luggagePreference = luggagePreference;
        this.updatedAt = Instant.now();
    }

    @jakarta.persistence.PrePersist
    @jakarta.persistence.PreUpdate
    void touch() { updatedAt = Instant.now(); }

    public UUID getUserId() { return userId; }
    public String getLanguage() { return language; }
    public String getHomePlace() { return homePlace; }
    public String getWorkPlace() { return workPlace; }
    public String getCampusPlace() { return campusPlace; }
    public boolean isMusicAllowed() { return musicAllowed; }
    public boolean isSmokingAllowed() { return smokingAllowed; }
    public boolean isPetsAllowed() { return petsAllowed; }
    public String getLuggagePreference() { return luggagePreference; }
    public Instant getUpdatedAt() { return updatedAt; }
}
