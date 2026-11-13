package com.carshare.api.users;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationQueries;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

/** An admin editing someone's role follows the same rule as that person switching their own. */
class AdminUserServiceTest {
    private final UserRepository users = mock(UserRepository.class);
    private final ReservationQueries reservationQueries = mock(ReservationQueries.class);
    private AdminUserService service;
    private AppUser admin;

    @BeforeEach
    void setUp() {
        service = new AdminUserService(users, mock(UserAccountService.class), reservationQueries);
        admin = new AppUser("Admin", "+21611111111", "admin@carshare.tn", "hash", UserRole.ADMIN);
        when(users.findAllByRoleForUpdate(UserRole.ADMIN)).thenReturn(List.of(admin));
    }

    private AppUser account(UserRole role) {
        AppUser user = new AppUser("Yacine Jomni", "+21612345678", "yacine@carshare.tn", "hash", role);
        when(users.findForUpdate(user.getId())).thenReturn(Optional.of(user));
        return user;
    }

    private AuthDtos.AdminUpdateUserRequest edit(String role) {
        return new AuthDtos.AdminUpdateUserRequest("Yacine Jomni", "+21612345678", "yacine@carshare.tn", role);
    }

    @Test
    @DisplayName("a driver with an unfinished trip cannot be made a passenger by an admin either")
    void driverWithATripCannotBeSwitched() {
        AppUser driver = account(UserRole.DRIVER);
        when(reservationQueries.driverHasUnfinishedTrips(driver.getId())).thenReturn(true);

        ApiException error = assertThrows(ApiException.class,
                () -> service.updateUser(admin.getId(), driver.getId(), edit("passenger")));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertEquals("role_change_active_trips", error.getCode());
        assertEquals(UserRole.DRIVER, driver.getRole());
    }

    @Test
    @DisplayName("a driver with nothing running can be made a passenger")
    void idleDriverCanBeSwitched() {
        AppUser driver = account(UserRole.DRIVER);
        when(reservationQueries.driverHasUnfinishedTrips(driver.getId())).thenReturn(false);

        service.updateUser(admin.getId(), driver.getId(), edit("passenger"));

        assertEquals(UserRole.PASSENGER, driver.getRole());
    }

    @Test
    @DisplayName("a passenger can always be made a driver, and the trip check is not even asked")
    void passengerCanBecomeDriver() {
        AppUser passenger = account(UserRole.PASSENGER);

        service.updateUser(admin.getId(), passenger.getId(), edit("driver"));

        assertEquals(UserRole.DRIVER, passenger.getRole());
        org.mockito.Mockito.verifyNoInteractions(reservationQueries);
    }

    @Test
    @DisplayName("editing a driver without changing the role is not blocked by a running trip")
    void keepingTheRoleIsNotBlocked() {
        AppUser driver = account(UserRole.DRIVER);
        when(reservationQueries.driverHasUnfinishedTrips(driver.getId())).thenReturn(true);

        service.updateUser(admin.getId(), driver.getId(),
                new AuthDtos.AdminUpdateUserRequest("New Name", "+21612345678", "yacine@carshare.tn", "driver"));

        assertEquals("New Name", driver.getFullName());
        assertEquals(UserRole.DRIVER, driver.getRole());
    }
}
