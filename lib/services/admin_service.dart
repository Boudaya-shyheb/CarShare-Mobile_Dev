import '../models/admin_stats.dart';
import '../models/admin_trip.dart';
import '../models/trip.dart';
import 'api_client.dart';

/// The calls the trip admin screens add to the admin operations pages (which call the list
/// routes through ApiClient themselves). Every route here is under /api/admin, which only an
/// account with the admin role may use; anyone else gets a 403 that ApiClient turns into an
/// ApiException.
class AdminService {
  AdminService._();
  static final instance = AdminService._();
  final ApiClient _api = ApiClient.instance;

  /// All the dashboard counters in one call.
  Future<AdminStats> stats() async =>
      AdminStats.fromJson(await _api.get('/admin/stats'));

  Future<AdminTripDetail> tripDetails(String tripId) async =>
      AdminTripDetail.fromJson(await _api.get('/admin/trips/$tripId'));

  /// Calls a trip off. The API applies the usual rules (a 409 if the trip can no longer be
  /// cancelled), releases the seats and records the admin as the one who did it.
  Future<Trip> cancelTrip(String tripId, String reason) async => Trip.fromJson(
    await _api.post('/admin/trips/$tripId/cancel', {'reason': reason}),
  );
}
