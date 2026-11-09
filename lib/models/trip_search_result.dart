/// One row of `GET /trips/search`, carrying the match score the results list shows.
class TripSearchResult {
  const TripSearchResult({
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.originLabel,
    required this.destinationLabel,
    required this.departureTime,
    required this.expectedArrival,
    this.durationS,
    required this.seatsAvailable,
    required this.pricePerSeat,
    required this.instantBooking,
    this.driverRating,
    this.driverRatingCount = 0,
    required this.pickupDistanceM,
    required this.dropoffDistanceM,
    required this.timeGapMin,
    required this.matchScore,
  });

  final String tripId;
  final String driverId;
  final String driverName;
  final String originLabel;
  final String destinationLabel;
  final DateTime departureTime;

  /// Always present. Falls back to the API's two-hour window when the trip carries no
  /// route, so a result card can show "08:15 → 09:30" without opening each trip.
  final DateTime expectedArrival;

  /// The published route's duration, or null when the trip has no route — which is how a
  /// measured arrival is told apart from the assumed one.
  final int? durationS;
  final int seatsAvailable;
  final double pricePerSeat;
  final bool instantBooking;

  /// Mean of the driver's last 50 ratings, null when nobody has rated them yet.
  final double? driverRating;
  final int driverRatingCount;

  /// How far the trip's pickup point is from where the passenger asked to be collected.
  final int pickupDistanceM;
  final int dropoffDistanceM;
  final int timeGapMin;

  /// 0–100. The server only returns trips scoring 50 or more.
  final int matchScore;

  factory TripSearchResult.fromJson(Map<String, dynamic> json) =>
      TripSearchResult(
        tripId: json['tripId'] as String,
        driverId: json['driverId'] as String,
        driverName: json['driverName'] as String,
        originLabel: json['originLabel'] as String,
        destinationLabel: json['destinationLabel'] as String,
        departureTime: DateTime.parse(json['departureTime'] as String),
        expectedArrival: json['expectedArrival'] == null
            ? DateTime.parse(json['departureTime'] as String)
                  .add(const Duration(hours: 2))
            : DateTime.parse(json['expectedArrival'] as String),
        durationS: json['durationS'] as int?,
        seatsAvailable: json['seatsAvailable'] as int,
        pricePerSeat: (json['pricePerSeat'] as num).toDouble(),
        instantBooking: json['instantBooking'] as bool? ?? false,
        driverRating: (json['driverRating'] as num?)?.toDouble(),
        driverRatingCount: json['driverRatingCount'] as int? ?? 0,
        pickupDistanceM: json['pickupDistanceM'] as int? ?? 0,
        dropoffDistanceM: json['dropoffDistanceM'] as int? ?? 0,
        timeGapMin: json['timeGapMin'] as int? ?? 0,
        matchScore: json['matchScore'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'driverId': driverId,
    'driverName': driverName,
    'originLabel': originLabel,
    'destinationLabel': destinationLabel,
    'departureTime': departureTime.toUtc().toIso8601String(),
    'expectedArrival': expectedArrival.toUtc().toIso8601String(),
    'durationS': durationS,
    'seatsAvailable': seatsAvailable,
    'pricePerSeat': pricePerSeat,
    'instantBooking': instantBooking,
    'driverRating': driverRating,
    'driverRatingCount': driverRatingCount,
    'pickupDistanceM': pickupDistanceM,
    'dropoffDistanceM': dropoffDistanceM,
    'timeGapMin': timeGapMin,
    'matchScore': matchScore,
  };
}
