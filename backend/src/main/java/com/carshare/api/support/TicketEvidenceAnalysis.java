package com.carshare.api.support;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_evidence_analyses")
public class TicketEvidenceAnalysis {
    public enum Status { COMPLETE, PARTIAL, FAILED }
    @Id private UUID id;
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "evidence_id", nullable = false, unique = true) private TicketEvidence evidence;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private Status status;
    @Column(name = "detected_type", length = 120) private String detectedType;
    @Column(nullable = false, length = 64) private String sha256;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "duplicate_evidence_id")
    private TicketEvidence duplicateEvidence;
    @Column(columnDefinition = "text") private String metadata;
    @Column(name = "extracted_text", columnDefinition = "text") private String extractedText;
    @Column(name = "error_message", length = 500) private String errorMessage;
    @Column(name = "analyzed_at", nullable = false) private Instant analyzedAt;

    protected TicketEvidenceAnalysis() { }
    public TicketEvidenceAnalysis(TicketEvidence evidence, String sha256) {
        id = UUID.randomUUID(); this.evidence = evidence; this.sha256 = sha256;
        status = Status.PARTIAL; analyzedAt = Instant.now();
    }
    public void finish(Status status, String detectedType, TicketEvidence duplicate,
            String metadata, String extractedText, String errorMessage) {
        this.status = status; this.detectedType = detectedType; duplicateEvidence = duplicate;
        this.metadata = limit(metadata, 12000); this.extractedText = limit(extractedText, 12000);
        this.errorMessage = limit(errorMessage, 500); analyzedAt = Instant.now();
    }
    private String limit(String value, int max) {
        return value == null || value.length() <= max ? value : value.substring(0, max);
    }
    public UUID getId() { return id; }
    public TicketEvidence getEvidence() { return evidence; }
    public Status getStatus() { return status; }
    public String getDetectedType() { return detectedType; }
    public String getSha256() { return sha256; }
    public TicketEvidence getDuplicateEvidence() { return duplicateEvidence; }
    public String getMetadata() { return metadata; }
    public String getExtractedText() { return extractedText; }
    public String getErrorMessage() { return errorMessage; }
    public Instant getAnalyzedAt() { return analyzedAt; }
}
