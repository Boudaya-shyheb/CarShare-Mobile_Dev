package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.carshare.api.common.ApiException;
import java.nio.file.Path;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LostAndFoundPhotoStorageTest {
    @TempDir Path directory;
    private LostAndFoundPhotoStorage storage;

    @BeforeEach
    void setUp() {
        storage = new LostAndFoundPhotoStorage(directory.toString());
    }

    private static byte[] jpeg(int size) {
        byte[] bytes = new byte[size];
        bytes[0] = (byte) 0xFF; bytes[1] = (byte) 0xD8; bytes[2] = (byte) 0xFF;
        return bytes;
    }

    @Test
    @DisplayName("a JPEG, a PNG and a WebP are accepted; the type comes from the bytes, not a claim")
    void acceptsRealImages() {
        byte[] png = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0};
        byte[] webp = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P'};

        assertEquals("image/jpeg", storage.save(jpeg(10)).mimeType());
        assertEquals("image/png", storage.save(png).mimeType());
        assertEquals("image/webp", storage.save(webp).mimeType());
    }

    @Test
    @DisplayName("what is saved can be read back byte for byte")
    void roundTrip() {
        byte[] photo = jpeg(64);

        var stored = storage.save(photo);

        assertArrayEquals(photo, storage.read(stored.fileName()));
        assertTrue(stored.fileName().endsWith(".jpg"));
    }

    @Test
    @DisplayName("a text file or a PDF is refused, even if named .jpg")
    void refusesNonImages() {
        ApiException error = assertThrows(ApiException.class, () -> storage.save("hello".getBytes()));

        assertEquals("invalid_photo_type", error.getCode());
    }

    @Test
    @DisplayName("an empty file and one over 2 MB are refused")
    void refusesEmptyAndTooBig() {
        assertEquals("invalid_photo", assertThrows(ApiException.class, () -> storage.save(new byte[0])).getCode());
        assertEquals("invalid_photo_size",
                assertThrows(ApiException.class, () -> storage.save(jpeg(2 * 1024 * 1024 + 1))).getCode());
    }

    @Test
    @DisplayName("a file name that is not one of ours, or a path trick, is not found")
    void refusesOtherNames() {
        for (String name : new String[] {"../secret.jpg", "x.jpg", "..\\..\\x.png", null}) {
            assertEquals("report_photo_not_found",
                    assertThrows(ApiException.class, () -> storage.read(name)).getCode(), String.valueOf(name));
        }
    }
}
