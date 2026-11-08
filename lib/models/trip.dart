/// A published trip.
///
/// Covers both shapes the API returns: the short `TripSummary` of `GET /trips/mine`, and the
/// full `TripDetail` of every trip write. The fields only `TripDetail` carries are nullable, so
/// one class reads both — see docs/reservation-api.md.
class Trip {
  const Trip({
    required this.id,
    required this.originLabel,
    required this.destinationLabel,
    required this.departureTime,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.pricePerSeat,
    required this.status,
    required this.instantBooking,
    this.distanceM,
    this.durationS,
    this.driverId,
    this.driverName,
    this.vehicleId,
    this.originLat,
    this.originLng,
    this.destinationLat,
    this.destinationLng,
    this.confirmedSeats,
    this.locked,
    this.notes,
    this.cancelReason,
    this.routePolyline,
    this.createdAt,
    this.updatedAt,
  });

  // --- on both shapes ---
  final String id;
  final String originLabel;
  final String destinationLabel;
  final DateTime departureTime;
  final int seatsTotal;
  final int seatsAvailable;
  final double pricePerSeat;
  final String status;
  final bool instantBooking;
  final int? distanceM;
  final int? durationS;

  // --- TripDetail only ---
  final String? driverId;
  final String? driverName;
  final String? vehicleId;
  final double? originLat;
  final double? originLng;
  final double? destinationLat;
  final double? destinationLng;
  final int? confirmedSeats;
  final bool? locked;
  final String? notes;
  final String? cancelReason;
  final String? routePolyline;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True when this came from an endpoint that returns the full detail.
  bool get hasCoordinates => originLat != null && destinationLat != null;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    originLabel: json['originLabel'] as String,
    destinationLabel: json['destinationLabel'] as String,
    departureTime: DateTime.parse(json['departureTime'] as String),
    seatsTotal: json['seatsTotal'] as int,
    seatsAvailable: json['seatsAvailable'] as int,
    pricePerSeat: (json['pricePerSeat'] as num).toDouble(),
    status: json['status'] as String,
    instantBooking: json['instantBooking'] as bool? ?? false,
    distanceM: json['distanceM'] as int?,
    durationS: json['durationS'] as int?,
    driverId: json['driverId'] as String?,
    driverName: json['driverName'] as String?,
    vehicleId: json['vehicleId'] as String?,
    originLat: (json['originLat'] as num?)?.toDouble(),
    originLng: (json['originLng'] as num?)?.toDouble(),
    destinationLat: (json['destinationLat'] as num?)?.toDouble(),
    destinationLng: (json['destinationLng'] as num?)?.toDouble(),
    confirmedSeats: json['confirmedSeats'] as int?,
    locked: json['locked'] as bool?,
    notes: json['notes'] as String?,
    cancelReason: json['cancelReason'] as String?,
    routePolyline: json['routePolyline'] as String?,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
  );

  /// The publish and update body. Both endpoints take exactly these fields.
  Map<String, dynamic> toJson() => {
    'vehicleId': vehicleId,
    'originLabel': originLabel,
    'originLat': originLat,
    'originLng': originLng,
    'destinationLabel': destinationLabel,
    'destinationLat': destinationLat,
    'destinationLng': destinationLng,
    'departureTime': departureTime.toUtc().toIso8601String(),
    'seatsTotal': seatsTotal,
    'pricePerSeat': pricePerSeat,
    'instantBooking': instantBooking,
    'notes': notes,
    'distanceM': distanceM,
    'durationS': durationS,
    'routePolyline': routePolyline,
  };
}
