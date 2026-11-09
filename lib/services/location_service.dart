import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Why the app has no position, and what to tell the user about it.
enum LocationProblem {
  /// Location is switched off on the device itself.
  serviceOff,

  /// The user said no this time.
  denied,

  /// The user said "don't ask again"; only Settings can undo it.
  deniedForever,

  /// The device had location on and permission granted, but gave nothing back.
  unavailable,
}

/// A position, or the reason there isn't one. The map falls back to [LocationService.tunisCentre]
/// whenever [point] is null, so every screen stays usable without location.
class LocationResult {
  const LocationResult.found(this.lat, this.lng)
    : problem = null,
      message = null;

  const LocationResult.missing(this.problem, this.message)
    : lat = null,
      lng = null;

  final double? lat;
  final double? lng;
  final LocationProblem? problem;

  /// A sentence to show in a SnackBar. Null when the position was found.
  final String? message;

  bool get hasPosition => lat != null && lng != null;

  /// True when sending the user to Settings is the only way to fix it.
  bool get needsSettings => problem == LocationProblem.deniedForever;
}

/// Permission handling and the device position, over geolocator.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Where the map sits when there is no position: central Tunis.
  static const tunisLat = 36.8065;
  static const tunisLng = 10.1815;

  /// Asks for permission if it has not been granted, then reads the position.
  ///
  /// Never throws: every failure comes back as a [LocationResult] with a message, so a screen
  /// can show it and carry on with the fallback centre.
  Future<LocationResult> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.missing(
          LocationProblem.serviceOff,
          'Location is switched off. Turn it on to centre the map on you — '
          'showing Tunis for now.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.missing(
          LocationProblem.deniedForever,
          'Location is blocked for CarShare. Allow it in Settings to centre the map on you — '
          'showing Tunis for now.',
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.missing(
          LocationProblem.denied,
          'Without location the map cannot centre on you — showing Tunis for now.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult.found(position.latitude, position.longitude);
    } on TimeoutException {
      return const LocationResult.missing(
        LocationProblem.unavailable,
        'Could not get a GPS fix in time — showing Tunis for now.',
      );
    } on Exception {
      // geolocator throws platform-specific types; none of them should break a screen.
      return const LocationResult.missing(
        LocationProblem.unavailable,
        'Could not read your location — showing Tunis for now.',
      );
    }
  }

  /// Opens the OS settings page where location permission can be granted again.
  Future<bool> openSettings() => Geolocator.openAppSettings();
}
