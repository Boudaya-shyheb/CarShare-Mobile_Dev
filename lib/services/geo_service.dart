import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/place.dart';
import 'api_client.dart';

/// The result of asking OSRM for a route between two points.
class RouteInfo {
  const RouteInfo({
    required this.polyline,
    required this.distanceM,
    required this.durationS,
  });

  /// Google encoded polyline, which is exactly what the API stores as `routePolyline`.
  final String polyline;
  final int distanceM;
  final int durationS;
}

/// Place search, reverse geocoding and routing, from the free OpenStreetMap services.
///
/// These are public endpoints with no API key, and both ask for a real User-Agent identifying
/// the application — Nominatim will block a client that does not send one. Callers must debounce
/// typing (the place search screen waits [searchDebounce]) so one request goes out per pause,
/// not one per keystroke.
class GeoService {
  GeoService._();
  static final GeoService instance = GeoService._();

  /// What the place search screen waits for after the last keystroke.
  static const searchDebounce = Duration(milliseconds: 400);

  static const _nominatim = 'https://nominatim.openstreetmap.org';
  static const _osrm = 'https://router.project-osrm.org';

  /// Nominatim's usage policy requires an identifying User-Agent on every call.
  ///
  /// Accept-Language matters as much: without it Nominatim answers in the local language, so a
  /// Tunisian search returns Arabic script ("سوسة") in an app that is otherwise English. French
  /// first, then English, gives the Latin names people here actually use ("Sousse", "Ennasr").
  static const _headers = {
    'User-Agent': 'CarShare-student-app',
    'Accept': 'application/json',
    'Accept-Language': 'fr,en',
  };

  static const _timeout = Duration(seconds: 15);

  /// Searches Tunisian places by name. Returns at most 8, and an empty list for a blank query.
  Future<List<Place>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    final uri = Uri.parse('$_nominatim/search').replace(
      queryParameters: {
        'q': trimmed,
        'format': 'jsonv2',
        'countrycodes': 'tn',
        'limit': '8',
        'addressdetails': '1',
      },
    );
    final decoded = await _getJson(uri);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_placeFromNominatim)
        .whereType<Place>()
        .toList(growable: false);
  }

  /// Turns a point into a street name, for the "Current location · …" row.
  /// Falls back to the coordinates themselves rather than failing the screen.
  Future<String> describePoint(double lat, double lng) async {
    final uri = Uri.parse('$_nominatim/reverse').replace(
      queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'jsonv2',
        'zoom': '16',
        'addressdetails': '1',
      },
    );
    try {
      final decoded = await _getJson(uri);
      if (decoded is Map<String, dynamic>) {
        final place = _placeFromNominatim(decoded);
        if (place != null) return place.label;
      }
    } on ApiException {
      // A missing street name must not stop the map from working.
    }
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// Asks OSRM for the driving route between two points, as an encoded polyline plus the
  /// distance and duration the publish form sends to the API.
  Future<RouteInfo?> route({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final path = '$originLng,$originLat;$destinationLng,$destinationLat';
    final uri = Uri.parse(
      '$_osrm/route/v1/driving/$path',
    ).replace(queryParameters: {'overview': 'full', 'geometries': 'polyline'});
    final decoded = await _getJson(uri);
    if (decoded is! Map<String, dynamic>) return null;
    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final best = routes.first;
    if (best is! Map<String, dynamic>) return null;
    final geometry = best['geometry'];
    if (geometry is! String) return null;
    return RouteInfo(
      polyline: geometry,
      distanceM: (best['distance'] as num? ?? 0).round(),
      durationS: (best['duration'] as num? ?? 0).round(),
    );
  }

  /// Decodes a Google encoded polyline into {latitude, longitude} pairs, for drawing the route.
  ///
  /// Tolerant on purpose: a truncated or corrupt string yields the points decoded so far, the
  /// same way the backend's GeoUtils does, so a bad route costs the line on the map and nothing
  /// more.
  List<List<double>> decodePolyline(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return const [];
    final points = <List<double>>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      final latStep = _decodeValue(encoded, index);
      if (latStep == null) break;
      final lngStep = _decodeValue(encoded, latStep.nextIndex);
      if (lngStep == null) break;
      lat += latStep.value;
      lng += lngStep.value;
      index = lngStep.nextIndex;
      points.add([lat / 1e5, lng / 1e5]);
    }
    return points;
  }

  // --- helpers ------------------------------------------------------------------------------

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final response = await http.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'The map service did not answer. Please try again.',
          statusCode: response.statusCode,
        );
      }
      return jsonDecode(response.body);
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'No internet connection, so places cannot be looked up.',
      );
    } on TimeoutException {
      throw const ApiException('The map service took too long. Try again.');
    } on http.ClientException {
      throw const ApiException(
        'No internet connection, so places cannot be looked up.',
      );
    } on FormatException {
      throw const ApiException(
        'The map service returned something unreadable.',
      );
    }
  }

  /// Nominatim's long `display_name` is a whole postal address; the first two parts read better
  /// on a one-line row ("Ennasr 2, Ariana").
  Place? _placeFromNominatim(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}');
    final lng = double.tryParse('${json['lon']}');
    if (lat == null || lng == null) return null;
    final display = json['display_name'] as String?;
    if (display == null || display.isEmpty) return null;
    final parts = display.split(',').map((part) => part.trim()).toList();
    final label = parts.length <= 2 ? display : parts.take(2).join(', ');
    return Place(label: label, lat: lat, lng: lng);
  }

  _Decoded? _decodeValue(String encoded, int start) {
    var result = 0;
    var shift = 0;
    var index = start;
    while (index < encoded.length) {
      final chunk = encoded.codeUnitAt(index) - 63;
      index++;
      if (chunk < 0) return null;
      result |= (chunk & 0x1f) << shift;
      if (chunk < 0x20) {
        return _Decoded(
          (result & 1) != 0 ? ~(result >> 1) : result >> 1,
          index,
        );
      }
      shift += 5;
      if (shift > 30) return null;
    }
    return null;
  }
}

class _Decoded {
  const _Decoded(this.value, this.nextIndex);
  final int value;
  final int nextIndex;
}
