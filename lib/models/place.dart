/// A point the passenger picked: from Nominatim, from the device, or from the map.
///
/// Not a server model — the API takes a label plus a latitude and longitude on each end of a
/// trip, and this is what the search form carries between screens.
class Place {
  const Place({required this.label, required this.lat, required this.lng});

  final String label;
  final double lat;
  final double lng;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    label: json['label'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {'label': label, 'lat': lat, 'lng': lng};

  /// True when two places are the same spot, which the search form refuses.
  /// Compared at about 11 m, the precision Nominatim and the map picker return.
  bool isSameSpotAs(Place other) =>
      (lat - other.lat).abs() < 0.0001 && (lng - other.lng).abs() < 0.0001;

  /// Just the first part of the label, for a header that has to fit on one line:
  /// "Sousse" out of "Sousse, Délégation Sousse Medina", and the "Current location"
  /// prefix dropped so a route reads "Ennozha → Sousse".
  String get shortLabel {
    final withoutPrefix = label.startsWith('Current location · ')
        ? label.substring('Current location · '.length)
        : label;
    final first = withoutPrefix.split(',').first.trim();
    return first.isEmpty ? withoutPrefix : first;
  }

  @override
  String toString() => label;
}
