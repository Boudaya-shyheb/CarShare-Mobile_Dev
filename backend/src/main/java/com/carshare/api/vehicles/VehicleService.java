package com.carshare.api.vehicles;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import com.carshare.api.users.ActiveUserGuard;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.time.Instant;
import java.time.Year;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Service
public class VehicleService {
    private final VehicleRepository vehicles;
    private final VehiclePhotoRepository photos;
    private final UserRepository users;
    private final VehiclePhotoStorage photoStorage;
    private final ReservationQueries reservationQueries;

    public VehicleService(
            VehicleRepository vehicles,
            VehiclePhotoRepository photos,
            UserRepository users,
            VehiclePhotoStorage photoStorage,
            ReservationQueries reservationQueries) {
        this.reservationQueries = reservationQueries;
        this.vehicles = vehicles;
        this.photos = photos;
        this.users = users;
        this.photoStorage = photoStorage;
    }

    @Transactional(readOnly = true)
    public List<VehicleDtos.VehicleResponse> getVehicles(UUID ownerId) {
        requireDriver(ownerId);
        List<Vehicle> owned = vehicles.findByOwner_IdOrderByCreatedAtDesc(ownerId);
        Map<UUID, Long> used = reservationQueries.completedTripsByVehicle(
                owned.stream().map(Vehicle::getId).toList());
        return owned.stream()
                .map(vehicle -> VehicleDtos.VehicleResponse.from(vehicle,
                        used.getOrDefault(vehicle.getId(), 0L)))
                .toList();
    }

    @Transactional(readOnly = true)
    public VehicleDtos.VehicleResponse getVehicle(UUID ownerId, UUID vehicleId) {
        requireDriver(ownerId);
        return respond(requireVehicle(ownerId, vehicleId));
    }

    @Transactional
    public VehicleDtos.VehicleResponse createVehicle(UUID ownerId, VehicleDtos.VehicleRequest request) {
        AppUser owner = requireActiveDriver(ownerId);
        String registrationNumber = validateRequest(request, null);
        Vehicle vehicle;
        try {
            vehicle = vehicles.saveAndFlush(new Vehicle(owner, request, registrationNumber));
        } catch (DataIntegrityViolationException exception) {
            throw registrationConflict(exception);
        }
        return respond(vehicle);
    }

    @Transactional
    public VehicleDtos.VehicleResponse updateVehicle(
            UUID ownerId, UUID vehicleId, VehicleDtos.VehicleRequest request) {
        requireActiveDriver(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        String registrationNumber = validateRequest(request, vehicleId);
        vehicle.update(request, registrationNumber);
        try {
            vehicles.flush();
        } catch (DataIntegrityViolationException exception) {
            throw registrationConflict(exception);
        }
        return respond(vehicle);
    }

    @Transactional
    public void deleteVehicle(UUID ownerId, UUID vehicleId) {
        requireActiveDriverForUpdate(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        if (reservationQueries.vehicleHasUpcomingTrips(vehicleId)) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_in_use",
                    "This vehicle is on a trip that has not finished. Cancel or finish the trip first.");
        }
        List<String> fileNames = vehicle.getPhotos().stream()
                .map(VehiclePhoto::getFileName).toList();
        boolean wasDefault = vehicle.isDefaultVehicle();
        vehicles.delete(vehicle);
        vehicles.flush();

        if (wasDefault) {
            vehicles.findActiveForDefault(ownerId).stream()
                    .filter(candidate -> !candidate.getId().equals(vehicleId))
                    .findFirst()
                    .ifPresent(candidate -> {
                        candidate.setDefault(Instant.now());
                        vehicles.save(candidate);
                    });
        }
        deleteFilesAfterCommit(fileNames);
    }

    @Transactional
    public VehicleDtos.VehicleResponse setDefault(UUID ownerId, UUID vehicleId) {
        requireActiveDriverForUpdate(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        if (vehicle.getStatus() != Vehicle.Status.ACTIVE) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_not_available",
                    "Only an active vehicle can be set as your default.");
        }
        if (vehicle.getReviewStatus() != Vehicle.ReviewStatus.APPROVED) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_not_reviewed",
                    "This vehicle must be approved by CarShare support before it can be used for a trip.");
        }

        vehicles.findByOwner_IdAndDefaultVehicleTrue(ownerId)
                .filter(current -> !current.getId().equals(vehicleId))
                .ifPresent(current -> {
                    current.clearDefault();
                    vehicles.saveAndFlush(current);
                });
        vehicle.setDefault(Instant.now());
        vehicles.flush();
        return respond(vehicle);
    }

    @Transactional
    public Vehicle validateForTrip(UUID ownerId, UUID vehicleId, int proposedSeats) {
        requireDriver(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        if (vehicle.getStatus() != Vehicle.Status.ACTIVE) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_not_available",
                    "This vehicle cannot be used for a new trip.");
        }
        if (vehicle.getReviewStatus() != Vehicle.ReviewStatus.APPROVED) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_not_approved",
                    "This vehicle must be approved by CarShare support before it can be used for a trip.");
        }
        if (proposedSeats < 1 || proposedSeats > vehicle.getSeatsNumber()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "trip_seats_exceed_vehicle_capacity",
                    "The trip seat count must not exceed the vehicle capacity.");
        }
        vehicle.markUsed(Instant.now());
        return vehicle;
    }

    /**
     * Removes every vehicle a user owns, photos included. Used when an account is deleted; the
     * caller has already checked that none is on a trip that has not finished. Trips keep their
     * history, since their vehicle id is set to null by the foreign key.
     */
    @Transactional
    public void deleteAllOwnedBy(UUID ownerId) {
        List<Vehicle> owned = vehicles.findByOwner_IdOrderByCreatedAtDesc(ownerId);
        List<String> fileNames = owned.stream().flatMap(vehicle -> vehicle.getPhotos().stream())
                .map(VehiclePhoto::getFileName).toList();
        vehicles.deleteAll(owned);
        vehicles.flush();
        deleteFilesAfterCommit(fileNames);
    }

    /**
     * The car on a trip, as a passenger may see it. {@code showPlate} is decided by the caller:
     * true for the driver and for people holding a seat.
     */
    @Transactional(readOnly = true)
    public VehicleDtos.TripVehicle tripVehicle(UUID vehicleId, boolean showPlate) {
        Vehicle vehicle = vehicles.findById(vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found",
                        "Vehicle not found."));
        return new VehicleDtos.TripVehicle(vehicle.getId(), vehicle.getBrand(), vehicle.getModel(),
                vehicle.getYear(), vehicle.getColor(),
                showPlate ? vehicle.getRegistrationNumber() : null, vehicle.getSeatsNumber(),
                vehicle.isAirConditioning(), !vehicle.getPhotos().isEmpty());
    }

    /** The vehicle's primary photo (or its first one), for the trip details screen. */
    @Transactional(readOnly = true)
    public PhotoContent primaryPhoto(UUID vehicleId) {
        Vehicle vehicle = vehicles.findById(vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found",
                        "Vehicle not found."));
        VehiclePhoto photo = vehicle.getPhotos().stream().filter(VehiclePhoto::isPrimaryPhoto)
                .findFirst().or(() -> vehicle.getPhotos().stream().findFirst())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                        "This vehicle has no photo."));
        return new PhotoContent(photoStorage.read(photo.getFileName()), photo.getMimeType());
    }

    private VehicleDtos.VehicleResponse respond(Vehicle vehicle) {
        long used = reservationQueries.completedTripsByVehicle(List.of(vehicle.getId()))
                .getOrDefault(vehicle.getId(), 0L);
        return VehicleDtos.VehicleResponse.from(vehicle, used);
    }

    @Transactional
    public void markReported(UUID vehicleId) {
        Vehicle vehicle = vehicles.findForUpdate(vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found",
                        "Vehicle not found."));
        vehicle.markReported();
    }

    @Transactional
    public VehicleDtos.VehicleResponse uploadPhoto(UUID ownerId, UUID vehicleId, byte[] bytes) {
        requireActiveDriver(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        if (bytes == null || bytes.length == 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_size",
                    "Choose an image smaller than 5 MB.");
        }
        if (bytes.length > VehiclePhotoStorage.MAX_FILE_SIZE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_size",
                    "Each vehicle photo must be 5 MB or smaller.");
        }
        if (photos.countByVehicle_Id(vehicleId) >= 4) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "vehicle_photo_limit",
                    "A vehicle can have up to four photos.");
        }

        boolean firstPhoto = photos.countByVehicle_Id(vehicleId) == 0;
        VehiclePhotoStorage.StoredPhoto stored = photoStorage.save(bytes);
        VehiclePhoto photo = new VehiclePhoto(stored.fileName(), stored.mimeType());
        photo.setPrimaryPhoto(firstPhoto);
        vehicle.addPhoto(photo);
        vehicle.clearReport();
        try {
            vehicles.flush();
        } catch (DataIntegrityViolationException exception) {
            photoStorage.delete(stored.fileName());
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_photo_conflict",
                    "The photo could not be added. Please try again.");
        }
        return respond(vehicle);
    }

    @Transactional(readOnly = true)
    public PhotoContent getPhoto(UUID ownerId, UUID vehicleId, UUID photoId) {
        requireDriver(ownerId);
        requireVehicle(ownerId, vehicleId);
        VehiclePhoto photo = photos.findByIdAndVehicle_Id(photoId, vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                        "Vehicle photo not found."));
        return new PhotoContent(photoStorage.read(photo.getFileName()), photo.getMimeType());
    }

    @Transactional(readOnly = true)
    public PhotoContent getAdminPhoto(UUID vehicleId, UUID photoId) {
        if (!vehicles.existsById(vehicleId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found", "Vehicle not found.");
        }
        VehiclePhoto photo = photos.findByIdAndVehicle_Id(photoId, vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                        "Vehicle photo not found."));
        return new PhotoContent(photoStorage.read(photo.getFileName()), photo.getMimeType());
    }

    @Transactional
    public VehicleDtos.VehicleResponse setPrimaryPhoto(UUID ownerId, UUID vehicleId, UUID photoId) {
        requireActiveDriver(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        VehiclePhoto selected = photos.findByIdAndVehicle_Id(photoId, vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                        "Vehicle photo not found."));
        if (selected.isPrimaryPhoto()) {
            return respond(vehicle);
        }

        vehicle.getPhotos().stream()
                .filter(VehiclePhoto::isPrimaryPhoto)
                .forEach(photo -> photo.setPrimaryPhoto(false));
        vehicles.flush();
        selected.setPrimaryPhoto(true);
        vehicles.flush();
        return respond(vehicle);
    }

    @Transactional
    public void deletePhoto(UUID ownerId, UUID vehicleId, UUID photoId) {
        requireActiveDriver(ownerId);
        Vehicle vehicle = requireVehicleForUpdate(ownerId, vehicleId);
        VehiclePhoto photo = photos.findByIdAndVehicle_Id(photoId, vehicleId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_photo_not_found",
                        "Vehicle photo not found."));
        String fileName = photo.getFileName();
        boolean wasPrimary = photo.isPrimaryPhoto();
        vehicle.removePhoto(photo);
        photos.delete(photo);
        photos.flush();
        if (wasPrimary) {
            photos.findByVehicle_IdOrderByCreatedAtAsc(vehicleId).stream()
                    .findFirst()
                    .ifPresent(replacement -> {
                        replacement.setPrimaryPhoto(true);
                        photos.flush();
                    });
        }
        deleteFilesAfterCommit(List.of(fileName));
    }

    private String validateRequest(VehicleDtos.VehicleRequest request, UUID currentVehicleId) {
        if (request.year() > Year.now().getValue()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_vehicle_year",
                    "The manufacturing year cannot be in the future.");
        }
        String registrationNumber = request.registrationNumber().replaceAll("\\s+", "").toUpperCase();
        boolean used = currentVehicleId == null
                ? vehicles.existsByRegistrationNumber(registrationNumber)
                : vehicles.existsByRegistrationNumberAndIdNot(registrationNumber, currentVehicleId);
        if (used) throw registrationConflict(null);
        return registrationNumber;
    }

    /** A driver who may make changes: not banned, not suspended. Reads use {@link #requireDriver}. */
    private AppUser requireActiveDriver(UUID ownerId) {
        AppUser user = requireDriver(ownerId);
        ActiveUserGuard.check(user, Instant.now());
        return user;
    }

    private AppUser requireActiveDriverForUpdate(UUID ownerId) {
        AppUser user = requireDriverForUpdate(ownerId);
        ActiveUserGuard.check(user, Instant.now());
        return user;
    }

    private AppUser requireDriver(UUID ownerId) {
        AppUser user = users.findById(ownerId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                        "account_not_found", "Your account could not be found."));
        if (user.getRole() != UserRole.DRIVER) {
            throw new ApiException(HttpStatus.FORBIDDEN, "driver_required",
                    "Only drivers can manage vehicles.");
        }
        return user;
    }

    private AppUser requireDriverForUpdate(UUID ownerId) {
        AppUser user = users.findForUpdate(ownerId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                        "account_not_found", "Your account could not be found."));
        if (user.getRole() != UserRole.DRIVER) {
            throw new ApiException(HttpStatus.FORBIDDEN, "driver_required",
                    "Only drivers can manage vehicles.");
        }
        return user;
    }

    private Vehicle requireVehicle(UUID ownerId, UUID vehicleId) {
        return vehicles.findByIdAndOwner_Id(vehicleId, ownerId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found",
                        "Vehicle not found."));
    }

    private Vehicle requireVehicleForUpdate(UUID ownerId, UUID vehicleId) {
        return vehicles.findOwnedForUpdate(vehicleId, ownerId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "vehicle_not_found",
                        "Vehicle not found."));
    }

    private ApiException registrationConflict(DataIntegrityViolationException exception) {
        if (exception == null) {
            return new ApiException(HttpStatus.CONFLICT, "registration_number_in_use",
                    "A vehicle with this registration number already exists.");
        }
        Throwable cause = exception;
        while (cause != null) {
            if (cause instanceof org.hibernate.exception.ConstraintViolationException violation
                    && "uq_vehicles_registration_number".equals(violation.getConstraintName())) {
                return new ApiException(HttpStatus.CONFLICT, "registration_number_in_use",
                        "A vehicle with this registration number already exists.");
            }
            cause = cause.getCause();
        }
        return new ApiException(HttpStatus.CONFLICT, "vehicle_conflict",
                "The vehicle could not be saved because its information conflicts with existing data.");
    }

    private void deleteFilesAfterCommit(List<String> fileNames) {
        if (fileNames.isEmpty()) return;
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                fileNames.forEach(photoStorage::delete);
            }
        });
    }

    public record PhotoContent(byte[] bytes, String mimeType) { }
}
