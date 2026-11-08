import '../models/live_view.dart';
import '../models/reservation.dart';
import '../models/trip.dart';
import '../models/trip_event.dart';
import '../models/trip_search_result.dart';
import 'api_client.dart';

/// One method per endpoint of the reservation module.
///
/// See docs/reservation-api.md for the JSON each one sends and returns, and the order of calls
/// for a full trip. Everything goes through [ApiClient], which adds the bearer token and turns
/// a failure into an [ApiException] carrying the server's `code`.
class ReservationService {
  ReservationService._();
  static final ReservationService instance = ReservationService._();

  final ApiClient _api = ApiClient.instance;

  // --- trips --------------------------------------------------------------------------------

  /// Publishes a trip. Driver accounts only.
  Future<Trip> publishTrip(Trip draft) async =>
      Trip.fromJson(await _api.post('/trips', draft.toJson()));

  /// The caller's own trips. [scope] is upcoming, past or cancelled; null for all of them.
  Future<List<Trip>> myTrips({String? scope}) async =>
      (await _api.getList('/trips/mine${scope == null ? '' : '?scope=$scope'}'))
          .map(Trip.fromJson)
          .toList(growable: false);

  /// Searches for trips matching a route and a time. Results come back ordered by [sort] and
  /// already filtered to a match score of 50 or more.
  Future<List<TripSearchResult>> searchTrips({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required DateTime departureTime,
    int seats = 1,
    String sort = 'best',
  }) async {
    final query = Uri(
      queryParameters: {
        'originLat': '$originLat',
        'originLng': '$originLng',
        'destinationLat': '$destinationLat',
        'destinationLng': '$destinationLng',
        'departureTime': departureTime.toUtc().toIso8601String(),
        'seats': '$seats',
        'sort': sort,
      },
    ).query;
    return (await _api.getList('/trips/search?$query'))
        .map(TripSearchResult.fromJson)
        .toList(growable: false);
  }

  Future<Trip> trip(String tripId) async =>
      Trip.fromJson(await _api.get('/trips/$tripId'));

  /// Edits a trip. Only while SCHEDULED, and the time, route and price are frozen once a
  /// reservation is confirmed (`trip_locked`).
  Future<Trip> updateTrip(String tripId, Trip draft) async =>
      Trip.fromJson(await _api.put('/trips/$tripId', draft.toJson()));

  /// Cancels a trip, which also closes every active reservation on it.
  Future<Trip> cancelTrip(String tripId, String reason) async => Trip.fromJson(
    await _api.post('/trips/$tripId/cancel', {'reason': reason}),
  );

  /// Moves the trip along by hand. Use [cancelTrip] for CANCELLED, which needs a reason.
  Future<Trip> changeTripStatus(
    String tripId,
    String status, {
    double? lat,
    double? lng,
  }) async => Trip.fromJson(
    await _api.post('/trips/$tripId/status', {
      'status': status,
      'lat': lat,
      'lng': lng,
    }),
  );

  /// The trip's audit trail, oldest first. Trip owner only.
  Future<List<TripEvent>> tripEvents(String tripId) async =>
      (await _api.getList('/trips/$tripId/events'))
          .map(TripEvent.fromJson)
          .toList(growable: false);

  // --- reservations -------------------------------------------------------------------------

  /// Books seats on a trip. Seats are held immediately; on an instant-booking trip the
  /// reservation comes back CONFIRMED with its pickup code.
  Future<Reservation> bookSeat(String tripId, int seats) async =>
      Reservation.fromJson(
        await _api.post('/trips/$tripId/reservations', {'seats': seats}),
      );

  /// The caller's own reservations. [scope] is upcoming, past or cancelled; null for all.
  Future<List<Reservation>> myReservations({String? scope}) async =>
      (await _api.getList(
        '/reservations/mine${scope == null ? '' : '?scope=$scope'}',
      )).map(Reservation.fromJson).toList(growable: false);

  /// Who booked a trip. Trip owner only, and never with a pickup code.
  Future<List<PassengerView>> tripReservations(String tripId) async =>
      (await _api.getList('/trips/$tripId/reservations'))
          .map(PassengerView.fromJson)
          .toList(growable: false);

  Future<PassengerView> acceptReservation(String reservationId) async =>
      PassengerView.fromJson(
        await _api.post('/reservations/$reservationId/accept'),
      );

  Future<PassengerView> refuseReservation(String reservationId) async =>
      PassengerView.fromJson(
        await _api.post('/reservations/$reservationId/refuse'),
      );

  /// Cancels the caller's own reservation. Free until two hours before departure; later the
  /// result comes back with `lateCancellation` true.
  Future<Reservation> cancelReservation(
    String reservationId,
    String reason,
  ) async => Reservation.fromJson(
    await _api.post('/reservations/$reservationId/cancel', {'reason': reason}),
  );

  // --- live tracking ------------------------------------------------------------------------

  /// Sends 1–50 GPS fixes. Trip owner only, and only while the trip is being tracked. Points
  /// less than 2 s apart are dropped by the server, so check `lastPositionAt` in the result to
  /// see how much of a buffer landed.
  Future<LiveView> sendPositions(
    String tripId,
    List<Map<String, dynamic>> points,
  ) async => LiveView.fromJson(
    await _api.post('/trips/$tripId/positions', {'points': points}),
  );

  /// The trip's live position. The driver, or a passenger whose reservation is CONFIRMED or
  /// COMPLETED. Built to be polled every 5 s.
  Future<LiveView> liveView(String tripId) async =>
      LiveView.fromJson(await _api.get('/trips/$tripId/live'));

  /// The driver types in the 4-digit code the passenger shows them. Three wrong codes lock
  /// check-in (`pickup_code_locked`).
  Future<PassengerView> checkIn(String reservationId, String code) async =>
      PassengerView.fromJson(
        await _api.post('/reservations/$reservationId/check-in', {
          'code': code,
        }),
      );

  /// Marks a passenger as a no-show, once the driver has waited five minutes.
  Future<PassengerView> markNoShow(String reservationId) async =>
      PassengerView.fromJson(
        await _api.post('/reservations/$reservationId/no-show'),
      );
}
