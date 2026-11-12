/// The figures on the Profile screen's Trips / Rating / No-shows card
/// (`GET /users/me/stats`).
class UserTripStats {
  const UserTripStats({
    required this.tripsAsDriver,
    required this.tripsAsPassenger,
    required this.totalTrips,
    required this.rating,
    required this.ratingCount,
    required this.noShows,
    required this.reliability,
  });

  /// Trips this user drove to the end, and seats they rode to the end.
  final int tripsAsDriver;
  final int tripsAsPassenger;
  final int totalTrips;

  /// Mean of the newest 50 ratings, null when nobody has rated them yet.
  final double? rating;
  final int ratingCount;

  /// Times a driver marked this user a no-show.
  final int noShows;

  /// The driver-reliability points the match score gives them, 0 to 15.
  final int reliability;

  factory UserTripStats.fromJson(Map<String, dynamic> json) => UserTripStats(
    tripsAsDriver: json['tripsAsDriver'] as int? ?? 0,
    tripsAsPassenger: json['tripsAsPassenger'] as int? ?? 0,
    totalTrips: json['totalTrips'] as int? ?? 0,
    rating: (json['rating'] as num?)?.toDouble(),
    ratingCount: json['ratingCount'] as int? ?? 0,
    noShows: json['noShows'] as int? ?? 0,
    reliability: json['reliability'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'tripsAsDriver': tripsAsDriver,
    'tripsAsPassenger': tripsAsPassenger,
    'totalTrips': totalTrips,
    'rating': rating,
    'ratingCount': ratingCount,
    'noShows': noShows,
    'reliability': reliability,
  };
}
