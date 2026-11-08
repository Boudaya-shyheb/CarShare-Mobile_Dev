/// One row of `GET /trips/search`, carrying the match score the results list shows.
class TripSearchResult {
  const TripSearchResult({
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.originLabel,
    required this.destinationLabel,
    required this.departureTime,
    required this.seatsAvailable,
    required this.pricePerSeat,
    required this.instantBooking,
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
  final int seatsAvailable;
  final double pricePerSeat;
  final bool instantBooking;

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
        seatsAvailable: json['seatsAvailable'] as int,
        pricePerSeat: (json['pricePerSeat'] as num).toDouble(),
        instantBooking: json['instantBooking'] as bool? ?? false,
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
    'seatsAvailable': seatsAvailable,
    'pricePerSeat': pricePerSeat,
    'instantBooking': instantBooking,
    'pickupDistanceM': pickupDistanceM,
    'dropoffDistanceM': dropoffDistanceM,
    'timeGapMin': timeGapMin,
    'matchScore': matchScore,
  };
}
