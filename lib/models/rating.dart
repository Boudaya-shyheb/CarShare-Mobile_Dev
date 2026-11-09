/// A score one person left another after a finished trip.
class Rating {
  const Rating({
    required this.id,
    required this.tripId,
    required this.fromUserId,
    required this.toUserId,
    required this.toUserName,
    required this.stars,
    required this.editable,
    this.comment,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tripId;
  final String fromUserId;
  final String toUserId;
  final String toUserName;
  final int stars;
  final String? comment;

  /// False once the 24-hour window has closed; the server decides, not the app.
  final bool editable;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Rating.fromJson(Map<String, dynamic> json) => Rating(
    id: json['id'] as String,
    tripId: json['tripId'] as String,
    fromUserId: json['fromUserId'] as String,
    toUserId: json['toUserId'] as String,
    toUserName: json['toUserName'] as String? ?? '',
    stars: json['stars'] as int,
    comment: json['comment'] as String?,
    editable: json['editable'] as bool? ?? false,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'toUserName': toUserName,
    'stars': stars,
    'comment': comment,
    'editable': editable,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

/// Somebody the signed-in user may rate on a trip, plus what they already said about them.
class RatableParty {
  const RatableParty({
    required this.userId,
    required this.name,
    required this.role,
    this.myRating,
  });

  final String userId;
  final String name;

  /// DRIVER or PASSENGER — which side of the trip this person was on.
  final String role;
  final Rating? myRating;

  bool get isRated => myRating != null;

  factory RatableParty.fromJson(Map<String, dynamic> json) => RatableParty(
    userId: json['userId'] as String,
    name: json['name'] as String? ?? '',
    role: json['role'] as String? ?? 'DRIVER',
    myRating: json['myRating'] == null
        ? null
        : Rating.fromJson(json['myRating'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'role': role,
    'myRating': myRating?.toJson(),
  };
}

/// What `GET /trips/{id}/ratings/mine` returns: everyone this user may rate on the trip.
class MyRatings {
  const MyRatings({
    required this.tripId,
    required this.tripCompleted,
    required this.parties,
  });

  final String tripId;
  final bool tripCompleted;
  final List<RatableParty> parties;

  factory MyRatings.fromJson(Map<String, dynamic> json) => MyRatings(
    tripId: json['tripId'] as String,
    tripCompleted: json['tripCompleted'] as bool? ?? false,
    parties: ((json['parties'] as List<dynamic>?) ?? const [])
        .map((row) => RatableParty.fromJson(row as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'tripCompleted': tripCompleted,
    'parties': parties.map((party) => party.toJson()).toList(growable: false),
  };
}

/// One fix of the driven track, for the replay on the completion screen.
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}
