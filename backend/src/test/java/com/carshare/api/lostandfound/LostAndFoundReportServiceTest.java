package com.carshare.api.lostandfound;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class LostAndFoundReportServiceTest {
    private final LostAndFoundReportRepository reports = mock(LostAndFoundReportRepository.class);
    private final TripRepository trips = mock(TripRepository.class);
    private final UserRepository users = mock(UserRepository.class);
    private final LostAndFoundHandoverRepository handoverRows = mock(LostAndFoundHandoverRepository.class);
    private final LostAndFoundNotificationService notifications = mock(LostAndFoundNotificationService.class);
    private final LostAndFoundPhotoStorage storage = mock(LostAndFoundPhotoStorage.class);
    private LostAndFoundReportService service;
    private AppUser driver;
    private AppUser passenger;
    private Trip trip;

    @BeforeEach
    void setUp() {
        service = new LostAndFoundReportService(reports, trips, mock(ReservationRepository.class), users,
                mock(LostAndFoundHandoverService.class), handoverRows, notifications, storage);
        driver = new AppUser("Yacine", "+21612345678", "yacine@carshare.tn", "h", UserRole.DRIVER);
        passenger = new AppUser("Ines", "+21698765432", "ines@carshare.tn", "h", UserRole.PASSENGER);
        trip = new Trip(driver, null, "Ennasr, Ariana", 36.8, 10.15, "Sousse", 35.8, 10.6,
                Instant.now().plusSeconds(7200), 3, new BigDecimal("10.00"), false, null, null, null, null);
        when(trips.findById(trip.getId())).thenReturn(Optional.of(trip));
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(users.findById(passenger.getId())).thenReturn(Optional.of(passenger));
        when(reports.save(any())).thenAnswer(call -> call.getArgument(0));
    }

    // --- creating a report ---------------------------------------------------------------------

    @Test
    @DisplayName("creating a report checks for a match afterwards, with the saved report")
    void createLooksForAMatch() {
        service.create(driver.getId(), trip.getId(), LostAndFoundReport.Type.FOUND, "Phone", "Black phone");

        verify(notifications).matchFoundFor(any(LostAndFoundReport.class));
    }

    @Test
    @DisplayName("a photo is stored and attached; the view says the report has one")
    void createStoresThePhoto() {
        byte[] photo = {1, 2, 3};
        when(storage.save(photo)).thenReturn(new LostAndFoundPhotoStorage.StoredPhoto(
                "11111111-1111-1111-1111-111111111111.jpg", "image/jpeg"));

        var view = service.create(driver.getId(), trip.getId(), LostAndFoundReport.Type.FOUND, "Phone", "Black", photo);

        assertTrue(view.hasPhoto());
        verify(storage).save(photo);
    }

    @Test
    @DisplayName("a report without a photo says so, and the storage is never touched")
    void createWithoutAPhoto() {
        var view = service.create(driver.getId(), trip.getId(), LostAndFoundReport.Type.FOUND, "Phone", "Black");

        assertFalse(view.hasPhoto());
        verify(storage, never()).save(any());
    }

    @Test
    @DisplayName("a refused photo fails the whole call: no match is announced")
    void badPhotoFailsTheCall() {
        byte[] photo = {1};
        when(storage.save(photo)).thenThrow(new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_type", "no"));

        ApiException error = assertThrows(ApiException.class, () -> service.create(driver.getId(), trip.getId(),
                LostAndFoundReport.Type.FOUND, "Phone", "Black", photo));

        assertEquals("invalid_photo_type", error.getCode());
        verify(notifications, never()).matchFoundFor(any());
    }

    // --- who may fetch a photo -----------------------------------------------------------------

    private LostAndFoundReport lostWithPhoto() {
        var lost = new LostAndFoundReport(trip, passenger, LostAndFoundReport.Type.LOST, "Phone", "Black\n\nColor: Black");
        lost.attachPhoto("11111111-1111-1111-1111-111111111111.jpg", "image/jpeg");
        when(reports.findById(lost.getId())).thenReturn(Optional.of(lost));
        when(storage.read("11111111-1111-1111-1111-111111111111.jpg")).thenReturn(new byte[] {9});
        when(handoverRows.findForReport(any(), any())).thenReturn(List.of());
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(lost));
        return lost;
    }

    @Test
    @DisplayName("the reporter can fetch their own photo")
    void reporterSeesTheirPhoto() {
        var lost = lostWithPhoto();

        var photo = service.photoOf(passenger.getId(), lost.getId());

        assertEquals("image/jpeg", photo.contentType());
        assertEquals(1, photo.bytes().length);
    }

    @Test
    @DisplayName("the person whose report matches it can fetch it, to recognise the item")
    void matchingReporterSeesThePhoto() {
        var lost = lostWithPhoto();
        var found = new LostAndFoundReport(trip, driver, LostAndFoundReport.Type.FOUND, "Phone", "Black phone\n\nColor: Black");
        when(reports.findByTrip_IdOrderByCreatedAtDesc(trip.getId())).thenReturn(List.of(found, lost));

        assertEquals(1, service.photoOf(driver.getId(), lost.getId()).bytes().length);
    }

    @Test
    @DisplayName("a participant of a handover holding the report can fetch it")
    void handoverParticipantSeesThePhoto() {
        var lost = lostWithPhoto();
        var found = new LostAndFoundReport(trip, driver, LostAndFoundReport.Type.FOUND, "Keys", "Keys");
        when(handoverRows.findForReport(any(), any())).thenReturn(List.of(new LostAndFoundHandover(trip, lost, found, passenger)));

        assertEquals(1, service.photoOf(driver.getId(), lost.getId()).bytes().length);
    }

    @Test
    @DisplayName("an administrator can fetch any report's photo")
    void adminSeesAnyPhoto() {
        var lost = lostWithPhoto();
        AppUser admin = new AppUser("Admin", "+21611111111", "admin@carshare.tn", "h", UserRole.ADMIN);
        when(users.findById(admin.getId())).thenReturn(Optional.of(admin));

        assertEquals(1, service.photoOf(admin.getId(), lost.getId()).bytes().length);
    }

    @Test
    @DisplayName("anybody else gets 404, never a hint that a photo exists")
    void strangerGetsNotFound() {
        var lost = lostWithPhoto();
        AppUser stranger = new AppUser("Sami", "+21655111222", "sami@carshare.tn", "h", UserRole.PASSENGER);
        when(users.findById(stranger.getId())).thenReturn(Optional.of(stranger));

        ApiException error = assertThrows(ApiException.class, () -> service.photoOf(stranger.getId(), lost.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("report_photo_not_found", error.getCode());
        verify(storage, never()).read(any());
    }

    @Test
    @DisplayName("a report without a photo answers 404 even to its owner")
    void noPhotoIsNotFound() {
        var lost = new LostAndFoundReport(trip, passenger, LostAndFoundReport.Type.LOST, "Phone", "Black");
        when(reports.findById(lost.getId())).thenReturn(Optional.of(lost));

        assertEquals("report_photo_not_found",
                assertThrows(ApiException.class, () -> service.photoOf(passenger.getId(), lost.getId())).getCode());
    }

    // --- one report by id ----------------------------------------------------------------------

    @Test
    @DisplayName("a reporter can open their own report by id, with its trip's route")
    void reportByIdForTheReporter() {
        var lost = lostWithPhoto();

        var view = service.reportById(passenger.getId(), lost.getId());

        assertEquals(lost.getId(), view.id());
        assertEquals("Ennasr, Ariana", view.originLabel());
        assertEquals("Sousse", view.destinationLabel());
        assertTrue(view.canResolve());
    }

    @Test
    @DisplayName("somebody with no part in the report gets 'not found'")
    void reportByIdForAStranger() {
        var lost = lostWithPhoto();
        var stranger = new AppUser("Sami", "+21655111222", "sami@carshare.tn", "h", UserRole.PASSENGER);
        when(users.findById(stranger.getId())).thenReturn(Optional.of(stranger));

        ApiException error = assertThrows(ApiException.class, () -> service.reportById(stranger.getId(), lost.getId()));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
    }
}
