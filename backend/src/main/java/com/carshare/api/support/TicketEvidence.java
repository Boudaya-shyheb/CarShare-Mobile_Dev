package com.carshare.api.support;

import com.carshare.api.users.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_evidence")
public class TicketEvidence {
    public enum Type { PHOTO, DOCUMENT, TRIP_DATA }

    @Id private UUID id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private SupportTicket ticket;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16) private Type type;
    @Column(name = "file_path", nullable = false, length = 500) private String filePath;
    @Column(name = "original_file_name", nullable = false, length = 255)
    private String originalFileName;
    @Column(name = "content_type", nullable = false, length = 100) private String contentType;
    @Column(name = "file_size", nullable = false) private long fileSize;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "uploaded_by_user_id")
    private AppUser uploadedBy;
    @Column(name = "created_at", nullable = false) private Instant createdAt;
    @Column(name = "updated_at", nullable = false) private Instant updatedAt;

    protected TicketEvidence() { }

    public TicketEvidence(SupportTicket ticket, Type type, String filePath, String originalFileName,
            String contentType, long fileSize, AppUser uploadedBy) {
        this.id = UUID.randomUUID();
        this.ticket = ticket;
        this.type = type;
        this.filePath = filePath;
        this.originalFileName = originalFileName;
        this.contentType = contentType;
        this.fileSize = fileSize;
        this.uploadedBy = uploadedBy;
    }

    @PrePersist
    void created() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void updated() { updatedAt = Instant.now(); }

    public UUID getId() { return id; }
    public SupportTicket getTicket() { return ticket; }
    public Type getType() { return type; }
    public String getFilePath() { return filePath; }
    public String getOriginalFileName() { return originalFileName; }
    public String getContentType() { return contentType; }
    public long getFileSize() { return fileSize; }
    public AppUser getUploadedBy() { return uploadedBy; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
