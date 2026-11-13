package com.carshare.api.vehicles;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

@ExtendWith(MockitoExtension.class)
class VehicleServiceTest {
    @Mock private VehicleRepository vehicles;
    @Mock private VehiclePhotoRepository photos;
    @Mock private UserRepository users;
    @Mock private VehiclePhotoStorage photoStorage;
    @Mock private ReservationQueries reservationQueries;

    private VehicleService service;
    private AppUser driver;

    @BeforeEach
    void setUp() {
        service = new VehicleService(vehicles, photos, users, photoStorage, reservationQueries);
        driver = new AppUser("Yacine Jomni", "+21612345678", "driver@carshare.tn", "hash", UserRole.DRIVER);
    }

    private Vehicle vehicle(int seats) {
        return new Vehicle(driver, new VehicleDtos.VehicleRequest("Peugeot", "208", 2022, "Black",
                "123 TU 4567", seats, Vehicle.TrunkSize.MEDIUM, true, null, null), "123 TU 4567");
    }

    private Vehicle approved(int seats) {
        Vehicle vehicle = vehicle(seats);
        vehicle.review(Vehicle.ReviewStatus.APPROVED, null);
        return vehicle;
    }

    private void owns(Vehicle vehicle) {
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(vehicles.findOwnedForUpdate(vehicle.getId(), driver.getId())).thenReturn(Optional.of(vehicle));
    }

    // --- the rules a trip's vehicle must meet -------------------------------------------------

    @Test
    @DisplayName("an approved, active vehicle with enough seats is accepted")
    void acceptsAnApprovedVehicle() {
        Vehicle car = approved(4);
        owns(car);

        assertEquals(car, service.validateForTrip(driver.getId(), car.getId(), 3));
    }

    @Test
    @DisplayName("a vehicle that is still pending gives vehicle_not_approved")
    void refusesAPendingVehicle() {
        Vehicle car = vehicle(4);
        owns(car);

        ApiException error = assertThrows(ApiException.class,
                () -> service.validateForTrip(driver.getId(), car.getId(), 3));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("vehicle_not_approved", error.getCode());
    }

    @Test
    @DisplayName("a rejected vehicle gives vehicle_not_approved")
    void refusesARejectedVehicle() {
        Vehicle car = vehicle(4);
        car.review(Vehicle.ReviewStatus.REJECTED, "plate unreadable");
        owns(car);

        ApiException error = assertThrows(ApiException.class,
                () -> service.validateForTrip(driver.getId(), car.getId(), 3));

        assertEquals("vehicle_not_approved", error.getCode());
    }

    @Test
    @DisplayName("a reported vehicle is not available for a new trip")
    void refusesAReportedVehicle() {
        Vehicle car = approved(4);
        car.markReported();
        owns(car);

        ApiException error = assertThrows(ApiException.class,
                () -> service.validateForTrip(driver.getId(), car.getId(), 3));

        assertEquals("vehicle_not_available", error.getCode());
    }

    @Test
    @DisplayName("somebody else's vehicle is a 404, never a hint that it exists")
    void refusesAnotherDriversVehicle() {
        UUID someoneElses = UUID.randomUUID();
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(vehicles.findOwnedForUpdate(someoneElses, driver.getId())).thenReturn(Optional.empty());

        ApiException error = assertThrows(ApiException.class,
                () -> service.validateForTrip(driver.getId(), someoneElses, 3));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("vehicle_not_found", error.getCode());
    }

    @Test
    @DisplayName("more seats than the vehicle offers is refused")
    void refusesMoreSeatsThanTheVehicleHas() {
        Vehicle car = approved(3);
        owns(car);

        ApiException error = assertThrows(ApiException.class,
                () -> service.validateForTrip(driver.getId(), car.getId(), 4));

        assertEquals("trip_seats_exceed_vehicle_capacity", error.getCode());
    }

    // --- used in N trips, and the car on a trip ----------------------------------------------

    @Test
    @DisplayName("the list carries each vehicle's completed-trip count, zero when it has none")
    void listCarriesTheCompletedTripCount() {
        Vehicle busy = approved(4);
        Vehicle idle = approved(4);
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(vehicles.findByOwner_IdOrderByCreatedAtDesc(driver.getId())).thenReturn(List.of(busy, idle));
        when(reservationQueries.completedTripsByVehicle(any())).thenReturn(Map.of(busy.getId(), 7L));

        List<VehicleDtos.VehicleResponse> list = service.getVehicles(driver.getId());

        assertEquals(7L, list.get(0).tripsCompleted());
        assertEquals(0L, list.get(1).tripsCompleted());
        assertEquals(Vehicle.ReviewStatus.APPROVED, list.get(0).reviewStatus());
    }

    @Test
    @DisplayName("a vehicle on a trip that has not finished cannot be deleted")
    void refusesToDeleteAVehicleOnAnUnfinishedTrip() {
        Vehicle car = approved(4);
        when(users.findForUpdate(driver.getId())).thenReturn(Optional.of(driver));
        when(vehicles.findOwnedForUpdate(car.getId(), driver.getId())).thenReturn(Optional.of(car));
        when(reservationQueries.vehicleHasUpcomingTrips(car.getId())).thenReturn(true);

        ApiException error = assertThrows(ApiException.class,
                () -> service.deleteVehicle(driver.getId(), car.getId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("vehicle_in_use", error.getCode());
        verify(vehicles, never()).delete(any(Vehicle.class));
    }

    @Test
    @DisplayName("the trip's vehicle view hides the plate unless the caller may see it")
    void tripVehicleHidesThePlate() {
        Vehicle car = approved(4);
        when(vehicles.findById(car.getId())).thenReturn(Optional.of(car));

        VehicleDtos.TripVehicle hidden = service.tripVehicle(car.getId(), false);
        VehicleDtos.TripVehicle shown = service.tripVehicle(car.getId(), true);

        assertNull(hidden.registrationNumber());
        assertEquals("123 TU 4567", shown.registrationNumber());
        assertEquals("Peugeot", hidden.brand());
        assertTrue(!hidden.hasPhoto());
    }

    // --- a suspended or banned owner -----------------------------------------------------------

    @Test
    @DisplayName("a suspended owner cannot add, edit, delete or change a vehicle, but can still list them")
    void suspendedOwnerCannotChangeVehicles() {
        driver.updateAccountStatus(com.carshare.api.users.UserStatus.SUSPENDED,
                java.time.Instant.now().plus(1, java.time.temporal.ChronoUnit.DAYS));
        when(users.findById(driver.getId())).thenReturn(Optional.of(driver));
        when(users.findForUpdate(driver.getId())).thenReturn(Optional.of(driver));
        VehicleDtos.VehicleRequest request = new VehicleDtos.VehicleRequest("Peugeot", "208", 2022, "Black",
                "123 TU 4567", 4, Vehicle.TrunkSize.MEDIUM, true, null, null);
        UUID someVehicle = UUID.randomUUID();

        for (Runnable change : List.<Runnable>of(
                () -> service.createVehicle(driver.getId(), request),
                () -> service.updateVehicle(driver.getId(), someVehicle, request),
                () -> service.deleteVehicle(driver.getId(), someVehicle),
                () -> service.setDefault(driver.getId(), someVehicle),
                () -> service.uploadPhoto(driver.getId(), someVehicle, new byte[] {1}),
                () -> service.setPrimaryPhoto(driver.getId(), someVehicle, UUID.randomUUID()),
                () -> service.deletePhoto(driver.getId(), someVehicle, UUID.randomUUID()))) {
            assertEquals("account_suspended", assertThrows(ApiException.class, change::run).getCode());
        }
        verify(vehicles, never()).saveAndFlush(any());

        when(vehicles.findByOwner_IdOrderByCreatedAtDesc(driver.getId())).thenReturn(List.of());
        assertEquals(0, service.getVehicles(driver.getId()).size());
    }
}
