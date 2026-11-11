package com.carshare.api.users;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "app_users", uniqueConstraints = @UniqueConstraint(name = "uq_app_users_email", columnNames = "email"))
public class AppUser {
    @Id private UUID id;
    @Column(name = "full_name", nullable = false, length = 100) private String fullName;
    @Column(nullable = false, length = 24) private String phone;
    @Column(nullable = false, length = 254) private String email;
    @Column(name = "password_hash", nullable = false, length = 100) private String passwordHash;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 16) private UserRole role;
    @Enumerated(EnumType.STRING) @Column(name = "account_status", nullable = false, length = 16) private UserStatus accountStatus = UserStatus.ACTIVE;
    @Column(name = "status_until") private Instant statusUntil;
    @Column(name = "status_reason", length = 500) private String statusReason;
    @Column(name = "status_manually_set", nullable = false) private boolean statusManuallySet;
    @Column(name = "failed_sign_in_attempts", nullable = false) private int failedSignInAttempts;
    @Column(name = "sign_in_locked_until") private Instant signInLockedUntil;
    @Column(name = "profile_photo", columnDefinition = "bytea") private byte[] profilePhoto;
    @Column(name = "profile_photo_mime_type", length = 50) private String profilePhotoMimeType;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected AppUser() { }

    public AppUser(String fullName, String phone, String email, String passwordHash, UserRole role) {
        this.id = UUID.randomUUID();
        this.fullName = fullName;
        this.phone = phone;
        this.email = email;
        this.passwordHash = passwordHash;
        this.role = role;
    }

    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }
    public UUID getId() { return id; }
    public String getFullName() { return fullName; }
    public String getPhone() { return phone; }
    public String getEmail() { return email; }
    public String getPasswordHash() { return passwordHash; }
    public UserRole getRole() { return role; }
    public UserStatus getAccountStatus() { return accountStatus; }
    public Instant getStatusUntil() { return statusUntil; }
    public String getStatusReason() { return statusReason; }
    public boolean isStatusManuallySet() { return statusManuallySet; }
    public int getFailedSignInAttempts() { return failedSignInAttempts; }
    public Instant getSignInLockedUntil() { return signInLockedUntil; }
    public byte[] getProfilePhoto() { return profilePhoto; }
    public String getProfilePhotoMimeType() { return profilePhotoMimeType; }
    public Instant getCreatedAt() { return createdAt; }
    public void changePasswordHash(String value) { passwordHash = value; }
    public void updateProfile(String fullName, String phone, String email, UserRole role) {
        this.fullName = fullName;
        this.phone = phone;
        this.email = email;
        this.role = role;
    }
    public boolean hasActiveSignInLock(Instant now) {
        return signInLockedUntil != null && signInLockedUntil.isAfter(now);
    }
    public void recordFailedSignIn(Instant now) {
        if (!hasActiveSignInLock(now)) {
            failedSignInAttempts = 0;
            signInLockedUntil = null;
        }
        failedSignInAttempts++;
        if (failedSignInAttempts >= 5) {
            failedSignInAttempts = 0;
            signInLockedUntil = now.plusSeconds(15 * 60);
        }
    }
    public void recordSuccessfulSignIn() {
        failedSignInAttempts = 0;
        signInLockedUntil = null;
    }
    public void updateAccountStatus(UserStatus status, Instant until) {
        accountStatus = status;
        statusUntil = until;
        statusReason = null;
        statusManuallySet = false;
    }
    public void updateAccountStatusByAdmin(UserStatus status, Instant until, String reason) {
        accountStatus = status;
        statusUntil = until;
        statusReason = reason;
        statusManuallySet = status != UserStatus.ACTIVE;
    }
    public void clearAdminStatusOverride() {
        statusManuallySet = false;
        statusReason = null;
    }
    public void clearExpiredAdminStatus() {
        statusManuallySet = false;
        statusReason = null;
    }
    public void updateProfilePhoto(byte[] photo, String mimeType) {
        profilePhoto = photo;
        profilePhotoMimeType = mimeType;
    }
}
