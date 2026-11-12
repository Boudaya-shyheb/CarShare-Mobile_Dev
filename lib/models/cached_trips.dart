/// One row of the `cached_trips` table: the last answer My trips got from the API, kept as text
/// so it can be shown again when the phone is offline.
///
/// There is one row per user, per [kind] (a driver's trips or a passenger's reservations) and
/// per [scope] (the Upcoming, Past and Cancelled tabs).
class CachedTrips {
  const CachedTrips({
    required this.userId,
    required this.kind,
    required this.scope,
    required this.json,
    required this.cachedAt,
  });

  factory CachedTrips.fromMap(Map<String, Object?> map) => CachedTrips(
    userId: map['user_id'] as String,
    kind: map['kind'] as String,
    scope: map['scope'] as String,
    json: map['json'] as String,
    cachedAt: DateTime.parse(map['cached_at'] as String),
  );

  final String userId;

  /// 'driver' or 'passenger'.
  final String kind;

  /// 'upcoming', 'past' or 'cancelled'.
  final String scope;

  /// The API's JSON list, exactly as it came back.
  final String json;
  final DateTime cachedAt;

  Map<String, Object?> toMap() => {
    'user_id': userId,
    'kind': kind,
    'scope': scope,
    'json': json,
    'cached_at': cachedAt.toUtc().toIso8601String(),
  };
}
