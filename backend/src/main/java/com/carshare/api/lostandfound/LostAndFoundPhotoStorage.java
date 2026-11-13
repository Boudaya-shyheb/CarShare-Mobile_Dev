package com.carshare.api.lostandfound;

import com.carshare.api.common.ApiException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/**
 * Where Lost & Found photos live on disk, in a folder that is not committed. Same style as the
 * Support evidence and vehicle photos: a random file name, the real image type read from the
 * file's first bytes (never from what the client claims), and a size limit.
 */
@Component
public class LostAndFoundPhotoStorage {
    static final int MAX_FILE_SIZE = 2 * 1024 * 1024;
    private final Path directory;

    public LostAndFoundPhotoStorage(
            @Value("${carshare.uploads.lost-and-found-directory:public/uploads/lost-and-found}") String directory) {
        this.directory = Path.of(directory).toAbsolutePath().normalize();
    }

    public StoredPhoto save(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo", "The photo is empty.");
        }
        if (bytes.length > MAX_FILE_SIZE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_size",
                    "Choose a photo smaller than 2 MB.");
        }
        String extension;
        String mimeType;
        if (isJpeg(bytes)) {
            extension = ".jpg";
            mimeType = "image/jpeg";
        } else if (isPng(bytes)) {
            extension = ".png";
            mimeType = "image/png";
        } else if (isWebp(bytes)) {
            extension = ".webp";
            mimeType = "image/webp";
        } else {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_type", "Choose a JPG, PNG, or WebP image.");
        }
        String fileName = UUID.randomUUID() + extension;
        try {
            Files.createDirectories(directory);
            Files.write(directory.resolve(fileName), bytes);
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "photo_storage_unavailable",
                    "The photo could not be saved. Please try again.");
        }
        return new StoredPhoto(fileName, mimeType);
    }

    public byte[] read(String fileName) {
        Path file = resolve(fileName);
        if (Files.notExists(file)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "report_photo_not_found", "This report has no photo.");
        }
        try {
            return Files.readAllBytes(file);
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "photo_storage_unavailable",
                    "The photo could not be loaded. Please try again.");
        }
    }

    private Path resolve(String fileName) {
        if (fileName == null || !fileName.matches("^[0-9a-fA-F-]{36}\\.(jpg|png|webp)$")) {
            throw new ApiException(HttpStatus.NOT_FOUND, "report_photo_not_found", "This report has no photo.");
        }
        return directory.resolve(fileName).normalize();
    }

    private static boolean isJpeg(byte[] b) {
        return b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF;
    }

    private static boolean isPng(byte[] b) {
        byte[] signature = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
        if (b.length < signature.length) return false;
        for (int i = 0; i < signature.length; i++) {
            if (b[i] != signature[i]) return false;
        }
        return true;
    }

    private static boolean isWebp(byte[] b) {
        return b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
                && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P';
    }

    public record StoredPhoto(String fileName, String mimeType) { }
}
