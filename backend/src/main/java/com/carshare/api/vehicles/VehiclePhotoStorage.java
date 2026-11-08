package com.carshare.api.vehicles;

import com.carshare.api.common.ApiException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class VehiclePhotoStorage {
    static final int MAX_FILE_SIZE = 5 * 1024 * 1024;
    private final Path directory;

    public VehiclePhotoStorage(
            @Value("${carshare.uploads.vehicle-directory:public/uploads/vehicles}") String directory) {
        this.directory = Path.of(directory).toAbsolutePath().normalize();
    }

    public StoredPhoto save(byte[] bytes) {
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
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_type",
                    "Choose a JPG, PNG, or WebP image.");
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
            throw new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                    "Vehicle photo not found.");
        }
        try {
            return Files.readAllBytes(file);
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "photo_storage_unavailable",
                    "The photo could not be loaded. Please try again.");
        }
    }

    public void delete(String fileName) {
        try {
            Files.deleteIfExists(resolve(fileName));
        } catch (IOException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "photo_storage_unavailable",
                    "The photo could not be removed. Please try again.");
        }
    }

    private Path resolve(String fileName) {
        if (fileName == null || !fileName.matches("^[0-9a-fA-F-]{36}\\.(jpg|png|webp)$")) {
            throw new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                    "Vehicle photo not found.");
        }
        return directory.resolve(fileName).normalize();
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

    public record StoredPhoto(String fileName, String mimeType) { }
}
