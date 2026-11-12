import 'place.dart';

/// One row of the `recent_searches` table: the two places of a search and when it was made.
///
/// Saved on the phone only, so it has `toMap` / `fromMap` (snake_case column names) instead of
/// the `toJson` / `fromJson` the API models use.
class RecentSearch {
  const RecentSearch({
    this.id,
    required this.userId,
    required this.originLabel,
    required this.originLat,
    required this.originLng,
    required this.destLabel,
    required this.destLat,
    required this.destLng,
    required this.searchedAt,
  });

  /// Builds the row for a search between two places. [id] stays null until SQLite picks one.
  factory RecentSearch.fromPlaces(
    String userId,
    Place from,
    Place to,
    DateTime searchedAt,
  ) => RecentSearch(
    userId: userId,
    originLabel: from.label,
    originLat: from.lat,
    originLng: from.lng,
    destLabel: to.label,
    destLat: to.lat,
    destLng: to.lng,
    searchedAt: searchedAt,
  );

  factory RecentSearch.fromMap(Map<String, Object?> map) => RecentSearch(
    id: map['id'] as int?,
    userId: map['user_id'] as String,
    originLabel: map['origin_label'] as String,
    originLat: (map['origin_lat'] as num).toDouble(),
    originLng: (map['origin_lng'] as num).toDouble(),
    destLabel: map['dest_label'] as String,
    destLat: (map['dest_lat'] as num).toDouble(),
    destLng: (map['dest_lng'] as num).toDouble(),
    searchedAt: DateTime.parse(map['searched_at'] as String),
  );

  final int? id;
  final String userId;
  final String originLabel;
  final double originLat;
  final double originLng;
  final String destLabel;
  final double destLat;
  final double destLng;
  final DateTime searchedAt;

  /// The two ends as the [Place]s the search form uses.
  Place get from => Place(label: originLabel, lat: originLat, lng: originLng);
  Place get to => Place(label: destLabel, lat: destLat, lng: destLng);

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'origin_label': originLabel,
    'origin_lat': originLat,
    'origin_lng': originLng,
    'dest_label': destLabel,
    'dest_lat': destLat,
    'dest_lng': destLng,
    'searched_at': searchedAt.toUtc().toIso8601String(),
  };
}
