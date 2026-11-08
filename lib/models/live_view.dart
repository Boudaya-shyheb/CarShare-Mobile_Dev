/// What `GET /trips/{id}/live` reports. The live tracking screen polls it every 5 s.
class LiveView {
  const LiveView({
    required this.tripStatus,
    required this.target,
    required this.deviating,
    this.lastLat,
    this.lastLng,
    this.lastPositionAt,
    this.distanceToTargetM,
    this.etaSeconds,
    this.myReservationStatus,
    this.checkedIn,
  });

  /// SCHEDULED, DRIVER_EN_ROUTE, DRIVER_ARRIVED, PICKED_UP, IN_PROGRESS, COMPLETED, CANCELLED.
  final String tripStatus;

  /// PICKUP until the passengers are aboard, then DROPOFF.
  final String target;

  /// True while the driver is more than 300 m off the planned route.
  final bool deviating;

  /// All null until the driver sends a first position.
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastPositionAt;
  final int? distanceToTargetM;
  final int? etaSeconds;

  /// Filled in only when a passenger is looking; null for the driver.
  final String? myReservationStatus;
  final bool? checkedIn;

  bool get hasPosition => lastLat != null && lastLng != null;
  bool get isHeadingToPickup => target == 'PICKUP';
  bool get isFinished => tripStatus == 'COMPLETED' || tripStatus == 'CANCELLED';

  factory LiveView.fromJson(Map<String, dynamic> json) => LiveView(
    tripStatus: json['tripStatus'] as String,
    target: json['target'] as String,
    deviating: json['deviating'] as bool? ?? false,
    lastLat: (json['lastLat'] as num?)?.toDouble(),
    lastLng: (json['lastLng'] as num?)?.toDouble(),
    lastPositionAt: json['lastPositionAt'] == null
        ? null
        : DateTime.parse(json['lastPositionAt'] as String),
    distanceToTargetM: json['distanceToTargetM'] as int?,
    etaSeconds: json['etaSeconds'] as int?,
    myReservationStatus: json['myReservationStatus'] as String?,
    checkedIn: json['checkedIn'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'tripStatus': tripStatus,
    'lastLat': lastLat,
    'lastLng': lastLng,
    'lastPositionAt': lastPositionAt?.toUtc().toIso8601String(),
    'target': target,
    'distanceToTargetM': distanceToTargetM,
    'etaSeconds': etaSeconds,
    'deviating': deviating,
    'myReservationStatus': myReservationStatus,
    'checkedIn': checkedIn,
  };
}
