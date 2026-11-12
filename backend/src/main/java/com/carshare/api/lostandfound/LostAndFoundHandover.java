package com.carshare.api.lostandfound;

import com.carshare.api.reservation.Trip;
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

/**
 * The handover of one lost item between its owner (the LOST report) and the finder (the FOUND
 * report). Both reporters see this one row; only the owner is ever shown the code.
 */
@Entity
@Table(name = "lost_and_found_handovers")
public class LostAndFoundHandover {

    /** Wrong codes the finder may type before the handover refuses any more tries. */
    public static final int MAX_FAILED_ATTEMPTS = 5;

    public enum Status {
        PROPOSED, ARRANGED, COMPLETED, CANCELLED;

        /** Still being worked on: it holds its two reports and counts for the one-live rule. */
        public boolean isActive() {
            return this == PROPOSED || this == ARRANGED;
        }
    }

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_id", nullable = false)
    private Trip trip;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "lost_report_id", nullable = false)
    private LostAndFoundReport lostReport;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "found_report_id", nullable = false)
    private LostAndFoundReport foundReport;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Status status;

    @Column(name = "meeting_point", length = 120)
    private String meetingPoint;

    @Column(name = "meeting_time", length = 80)
    private String meetingTime;

    @Column(length = 4)
    private String code;

    @Column(name = "failed_attempts", nullable = false)
    private short failedAttempts;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "created_by", nullable = false)
    private AppUser createdBy;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected LostAndFoundHandover() {
    }

    public LostAndFoundHandover(
            Trip trip, LostAndFoundReport lostReport, LostAndFoundReport foundReport,
            AppUser createdBy) {
        this.id = UUID.randomUUID();
        this.trip = trip;
        this.lostReport = lostReport;
        this.foundReport = foundReport;
        this.createdBy = createdBy;
        this.status = Status.PROPOSED;
        this.createdAt = Instant.now();
        this.updatedAt = createdAt;
    }

    public UUID getId() { return id; }
    public Trip getTrip() { return trip; }
    public LostAndFoundReport getLostReport() { return lostReport; }
    public LostAndFoundReport getFoundReport() { return foundReport; }
    public Status getStatus() { return status; }
    public String getMeetingPoint() { return meetingPoint; }
    public String getMeetingTime() { return meetingTime; }
    public String getCode() { return code; }
    public int getFailedAttempts() { return failedAttempts; }
    public AppUser getCreatedBy() { return createdBy; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    public boolean isLocked() {
        return failedAttempts >= MAX_FAILED_ATTEMPTS;
    }

    public int attemptsLeft() {
        return Math.max(0, MAX_FAILED_ATTEMPTS - failedAttempts);
    }

    /**
     * Sets the meeting point and time. The code is created the first time this runs and then
     * kept, so editing the meeting does not change what the owner already told the finder.
     */
    public void arrange(String meetingPoint, String meetingTime, String newCode) {
        this.meetingPoint = meetingPoint;
        this.meetingTime = meetingTime;
        if (this.code == null) {
            this.code = newCode;
        }
        this.status = Status.ARRANGED;
        touch();
    }

    public void recordFailedAttempt() {
        failedAttempts++;
        touch();
    }

    public void complete() {
        status = Status.COMPLETED;
        touch();
    }

    public void cancel() {
        status = Status.CANCELLED;
        touch();
    }

    private void touch() {
        updatedAt = Instant.now();
    }
}
