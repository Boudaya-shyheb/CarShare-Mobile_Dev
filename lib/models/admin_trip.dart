import 'reservation.dart';
import 'trip.dart';
import 'trip_event.dart';

/// One trip with everyone who booked it and everything that happened to it
/// (`GET /admin/trips/{id}`). The three parts reuse the app's existing models.
class AdminTripDetail {
  const AdminTripDetail({
    required this.trip,
    required this.reservations,
    required this.events,
  });

  final Trip trip;
  final List<PassengerView> reservations;
  final List<TripEvent> events;

  factory AdminTripDetail.fromJson(Map<String, dynamic> json) =>
      AdminTripDetail(
        trip: Trip.fromJson(json['trip'] as Map<String, dynamic>),
        reservations: (json['reservations'] as List)
            .map((row) => PassengerView.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
        events: (json['events'] as List)
            .map((row) => TripEvent.fromJson(row as Map<String, dynamic>))
            .toList(growable: false),
      );
}
