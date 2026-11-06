package com.carshare.api.users;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.util.UUID;
import org.hibernate.annotations.UuidGenerator;

@Entity
@Table(name = "user_emergency_contacts")
public class UserEmergencyContact {
    @Id
    @GeneratedValue
    @UuidGenerator
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser user;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, length = 24)
    private String phone;

    @Column(nullable = false, length = 40)
    private String relationship;

    protected UserEmergencyContact() { }

    public UserEmergencyContact(AppUser user, String name, String phone, String relationship) {
        this.user = user;
        update(name, phone, relationship);
    }

    public void update(String name, String phone, String relationship) {
        this.name = name;
        this.phone = phone;
        this.relationship = relationship;
    }

    public UUID getId() { return id; }
    public AppUser getUser() { return user; }
    public String getName() { return name; }
    public String getPhone() { return phone; }
    public String getRelationship() { return relationship; }
}
