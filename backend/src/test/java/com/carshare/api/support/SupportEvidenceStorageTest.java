package com.carshare.api.support;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.carshare.api.common.ApiException;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class SupportEvidenceStorageTest {
    @TempDir Path directory;

    @Test
    void storesReadsAndDeletesARealPdfSignature() {
        SupportEvidenceStorage storage = new SupportEvidenceStorage(directory.toString());
        byte[] bytes = "%PDF-1.7 test".getBytes(java.nio.charset.StandardCharsets.US_ASCII);

        SupportEvidenceStorage.StoredEvidence stored = storage.save(bytes);

        assertEquals("application/pdf", stored.mimeType());
        assertArrayEquals(bytes, storage.read(stored.fileName()));
        storage.delete(stored.fileName());
        assertThrows(ApiException.class, () -> storage.read(stored.fileName()));
    }

    @Test
    void rejectsAFileWhoseContentIsNotAllowed() {
        SupportEvidenceStorage storage = new SupportEvidenceStorage(directory.toString());

        assertThrows(ApiException.class, () -> storage.save(new byte[] {1, 2, 3, 4}));
    }
}
