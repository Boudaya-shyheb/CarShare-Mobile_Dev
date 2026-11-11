package com.carshare.api.support;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.ReservationRepository;
import com.carshare.api.reservation.ReservationStatus;
import com.carshare.api.reservation.TripRepository;
import com.carshare.api.users.UserRepository;
import java.util.List;
import java.util.UUID;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SupportService {
    private final SupportTicketRepository tickets;
    private final UserRepository users;
    private final TripRepository trips;
    private final ReservationRepository reservations;

    public SupportService(SupportTicketRepository tickets, UserRepository users,
            TripRepository trips, ReservationRepository reservations) {
        this.tickets = tickets;
        this.users = users;
        this.trips = trips;
        this.reservations = reservations;
    }

    @Transactional(readOnly = true)
    public List<TicketView> myTickets(UUID userId) {
        return tickets.findByUser_IdOrderByCreatedAtDesc(userId).stream().map(TicketView::from).toList();
    }

    @Transactional
    public TicketView create(UUID userId, TicketRequest request) {
        var user = users.findById(userId).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "account_not_found", "Your account could not be found."));
        String category = clean(request.category(), 60, "Category");
        String title = clean(request.title(), 120, "Title");
        String description = clean(request.description(), 1500, "Description");
        if (request.tripId() != null) {
            var trip = trips.findById(request.tripId()).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,
                    "trip_not_found", "The selected trip was not found."));
            boolean isDriver = trip.isDrivenBy(userId);
            boolean isPassenger = reservations.findByTrip_IdAndStatusIn(request.tripId(),
                    Set.of(ReservationStatus.CONFIRMED, ReservationStatus.COMPLETED)).stream()
                    .anyMatch(reservation -> reservation.getPassenger().getId().equals(userId));
            if (!isDriver && !isPassenger) throw new ApiException(HttpStatus.FORBIDDEN,
                    "not_trip_participant", "Only participants can report an issue about this trip.");
        }
        return TicketView.from(tickets.save(new SupportTicket(user, request.tripId(), category, title, description)));
    }

    private String clean(String value, int max, String label) {
        String text = value == null ? "" : value.strip();
        if (text.isEmpty() || text.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_ticket", label + " is required and must be no longer than " + max + " characters.");
        }
        return text;
    }

    public record TicketRequest(UUID tripId, String category, String title, String description) { }
    public record TicketView(UUID id, UUID userId, String userName, String userEmail, UUID tripId,
            String category, String title, String description, SupportTicket.Status status,
            String resolution, java.time.Instant createdAt, java.time.Instant updatedAt) {
        public static TicketView from(SupportTicket ticket) {
            return new TicketView(ticket.getId(), ticket.getUser().getId(), ticket.getUser().getFullName(),
                    ticket.getUser().getEmail(), ticket.getTripId(), ticket.getCategory(), ticket.getTitle(),
                    ticket.getDescription(), ticket.getStatus(), ticket.getResolution(),
                    ticket.getCreatedAt(), ticket.getUpdatedAt());
        }
    }
}
