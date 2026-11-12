package com.carshare.api.support;

import com.carshare.api.common.ApiException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class SupportEvidenceStorage {
    public static final int MAX_FILE_SIZE = 5 * 1024 * 1024;
    private final Path directory;

    public SupportEvidenceStorage(
            @Value("${carshare.uploads.support-directory:public/uploads/support}") String directory) {
        this.directory = Path.of(directory).toAbsolutePath().normalize();
    }

    public StoredEvidence save(byte[] bytes) {
        if (bytes.length == 0 || bytes.length > MAX_FILE_SIZE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_evidence_size",
                    "Evidence must be a non-empty file no larger than 5 MB.");
        }
        FileType type = detect(bytes);
        String fileName = UUID.randomUUID() + type.extension();
        try {
            Files.createDirectories(directory);
            Files.write(directory.resolve(fileName), bytes);
        } catch (IOException exception) {
            throw unavailable("The evidence could not be saved. Please try again.");
        }
        return new StoredEvidence(fileName, type.mimeType());
    }

    public byte[] read(String fileName) {
        Path file = resolve(fileName);
        if (Files.notExists(file)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "evidence_not_found",
                    "Evidence file not found.");
        }
        try {
            return Files.readAllBytes(file);
        } catch (IOException exception) {
            throw unavailable("The evidence could not be loaded. Please try again.");
        }
    }

    public void delete(String fileName) {
        try {
            Files.deleteIfExists(resolve(fileName));
        } catch (IOException exception) {
            throw unavailable("The evidence could not be removed. Please try again.");
        }
    }

    private Path resolve(String fileName) {
        if (fileName == null
                || !fileName.matches("^[0-9a-fA-F-]{36}\\.(jpg|png|webp|pdf)$")) {
            throw new ApiException(HttpStatus.NOT_FOUND, "evidence_not_found",
                    "Evidence file not found.");
        }
        Path resolved = directory.resolve(fileName).normalize();
        if (!resolved.startsWith(directory)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "evidence_not_found",
                    "Evidence file not found.");
        }
        return resolved;
    }

    private FileType detect(byte[] bytes) {
        if (isJpeg(bytes)) return new FileType(".jpg", "image/jpeg");
        if (isPng(bytes)) return new FileType(".png", "image/png");
        if (isWebp(bytes)) return new FileType(".webp", "image/webp");
        if (isPdf(bytes)) return new FileType(".pdf", "application/pdf");
        throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_evidence_type",
                "Choose a JPG, PNG, WebP, or PDF file.");
    }

    private boolean isJpeg(byte[] bytes) {
        return bytes.length >= 3 && (bytes[0] & 0xFF) == 0xFF
                && (bytes[1] & 0xFF) == 0xD8 && (bytes[2] & 0xFF) == 0xFF;
    }

    private boolean isPng(byte[] bytes) {
        byte[] signature = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
        if (bytes.length < signature.length) return false;
        for (int i = 0; i < signature.length; i++) {
            if (bytes[i] != signature[i]) return false;
        }
        return true;
    }

    private boolean isWebp(byte[] bytes) {
        return bytes.length >= 12 && bytes[0] == 'R' && bytes[1] == 'I'
                && bytes[2] == 'F' && bytes[3] == 'F'
                && bytes[8] == 'W' && bytes[9] == 'E'
                && bytes[10] == 'B' && bytes[11] == 'P';
    }

    private boolean isPdf(byte[] bytes) {
        return bytes.length >= 5 && bytes[0] == '%' && bytes[1] == 'P'
                && bytes[2] == 'D' && bytes[3] == 'F' && bytes[4] == '-';
    }

    private ApiException unavailable(String message) {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,
                "evidence_storage_unavailable", message);
    }

    private record FileType(String extension, String mimeType) { }
    public record StoredEvidence(String fileName, String mimeType) { }
}
