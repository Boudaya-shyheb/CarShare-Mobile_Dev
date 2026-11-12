import 'place.dart';

/// One row of the `favorite_places` table: a place the user saved under a short name such as
/// "Home" or "University". [label] is the full address, [name] is what the chip says.
class FavoritePlace {
  const FavoritePlace({
    this.id,
    required this.userId,
    required this.name,
    required this.label,
    required this.lat,
    required this.lng,
    required this.createdAt,
  });

  factory FavoritePlace.fromMap(Map<String, Object?> map) => FavoritePlace(
    id: map['id'] as int?,
    userId: map['user_id'] as String,
    name: map['name'] as String,
    label: map['label'] as String,
    lat: (map['lat'] as num).toDouble(),
    lng: (map['lng'] as num).toDouble(),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  final int? id;
  final String userId;
  final String name;
  final String label;
  final double lat;
  final double lng;
  final DateTime createdAt;

  /// The saved spot as the [Place] the search form uses.
  Place get place => Place(label: label, lat: lat, lng: lng);

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'name': name,
    'label': label,
    'lat': lat,
    'lng': lng,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
