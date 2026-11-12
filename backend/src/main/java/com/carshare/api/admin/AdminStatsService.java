package com.carshare.api.admin;

import com.carshare.api.lostandfound.LostAndFoundReportRepository;
import com.carshare.api.reservation.AdminTripDtos;
import com.carshare.api.reservation.AdminTripService;
import com.carshare.api.users.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Collects the dashboard counters from the modules that own the data. Trips and reservations are
 * counted by the Reservation module itself; users and lost-and-found reports are plain counts.
 */
@Service
public class AdminStatsService {
    private final UserRepository users;
    private final AdminTripService adminTrips;
    private final LostAndFoundReportRepository reports;

    public AdminStatsService(UserRepository users, AdminTripService adminTrips,
            LostAndFoundReportRepository reports) {
        this.users = users;
        this.adminTrips = adminTrips;
        this.reports = reports;
    }

    @Transactional(readOnly = true)
    public AdminDtos.Stats stats() {
        AdminTripDtos.TripCounts trips = adminTrips.counts();
        return new AdminDtos.Stats(users.count(), trips.total(), trips.inProgress(),
                trips.completed(), trips.cancelled(), trips.reservations(), reports.count());
    }
}
