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
    public Instant getCreatedAt() { return createdAt; }
    public void changePasswordHash(String value) { passwordHash = value; }
    public void updateProfile(String fullName, String phone, String email, UserRole role) {
        this.fullName = fullName;
        this.phone = phone;
        this.email = email;
        this.role = role;
    }
}
