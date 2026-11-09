/// One row of a trip's audit trail (`GET /trips/{id}/events`).
class TripEvent {
  const TripEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.lat,
    this.lng,
    this.detail,
  });

  final String id;

  /// PUBLISHED, UPDATED, DRIVER_EN_ROUTE, DRIVER_ARRIVED, PICKED_UP, IN_PROGRESS, COMPLETED,
  /// CANCELLED, CHECK_IN, CHECK_IN_FAILED, NO_SHOW, DEVIATION, DEVIATION_RESOLVED,
  /// RESERVATION_REQUESTED, RESERVATION_CONFIRMED, RESERVATION_REFUSED, RESERVATION_CANCELLED.
  final String type;
  final DateTime createdAt;

  /// Null when nobody decided it, such as an auto-refusal after the waiting window.
  final String? actorId;
  final double? lat;
  final double? lng;
  final String? detail;

  bool get hasPosition => lat != null && lng != null;

  factory TripEvent.fromJson(Map<String, dynamic> json) => TripEvent(
    id: json['id'] as String,
    type: json['type'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    actorId: json['actorId'] as String?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    detail: json['detail'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'actorId': actorId,
    'lat': lat,
    'lng': lng,
    'detail': detail,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
