package com.carshare.api.reservation;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * One person's score for another on a finished trip: a passenger rating their driver, or a
 * driver rating a passenger who boarded.
 *
 * <p>A rating may be changed for {@link #EDIT_WINDOW} after it was first left, which is long
 * enough to fix a mis-tap and short enough that an average stops moving under people's feet.
 */
@Entity
@Table(name = "ratings")
public class Rating {
    /** How long after leaving a rating it can still be changed. */
    public static final Duration EDIT_WINDOW = Duration.ofHours(24);

    public static final int MIN_STARS = 1;
    public static final int MAX_STARS = 5;

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "from_user_id", nullable = false)
    private AppUser from;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "to_user_id", nullable = false)
    private AppUser to;

    // SMALLINT in the migration.
    @Column(nullable = false) private short stars;

    @Column(length = 500) private String comment;

    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at") private Instant updatedAt;

    protected Rating() { }

    public Rating(Trip trip, AppUser from, AppUser to, int stars, String comment) {
        this.id = UUID.randomUUID();
        this.trip = trip;
        this.from = from;
        this.to = to;
        this.stars = (short) stars;
        this.comment = comment;
        // Stamped here rather than left to @PrePersist so the create response carries it.
        this.createdAt = Instant.now();
    }

    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }
    @PreUpdate void touch() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public Trip getTrip() { return trip; }
    public AppUser getFrom() { return from; }
    public AppUser getTo() { return to; }
    public int getStars() { return stars; }
    public String getComment() { return comment; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    /** True while the edit window is still open, measured from when the rating was left. */
    public boolean isEditableAt(Instant now) {
        return now.isBefore(createdAt.plus(EDIT_WINDOW));
    }

    /** Changes a rating already left. The service checks the window before calling this. */
    public void revise(int stars, String comment) {
        this.stars = (short) stars;
        this.comment = comment;
    }
}
