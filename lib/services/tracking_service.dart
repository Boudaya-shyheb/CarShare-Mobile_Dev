import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/live_view.dart';
import 'local_database.dart';
import 'reservation_service.dart';

/// Where fixes wait when the API cannot be reached.
///
/// An interface rather than a direct sqflite call so the flush rules can be tested without a
/// device: the production implementation is [SqfliteGpsBuffer], tests pass a list in memory.
abstract class GpsBuffer {
  Future<void> add(String tripId, List<Map<String, Object?>> points);

  /// The oldest waiting points, each with the `id` that [remove] takes.
  Future<List<Map<String, Object?>>> take(String tripId, {int limit});

  Future<void> remove(List<int> ids);

  Future<int> count(String tripId);
}

/// The sqflite-backed buffer the app really uses.
class SqfliteGpsBuffer implements GpsBuffer {
  const SqfliteGpsBuffer();

  LocalDatabase get _local => LocalDatabase.instance;

  @override
  Future<void> add(String tripId, List<Map<String, Object?>> points) =>
      _local.bufferGpsPoints(tripId, points);

  @override
  Future<List<Map<String, Object?>>> take(String tripId, {int limit = 50}) =>
      _local.pendingGpsPoints(tripId, limit: limit);

  @override
  Future<void> remove(List<int> ids) => _local.deleteGpsPoints(ids);

  @override
  Future<int> count(String tripId) => _local.pendingGpsCount(tripId);
}

/// What actually posts a batch. Injectable so a test can make a send fail on demand.
typedef PositionSender = Future<LiveView> Function(
  String tripId,
  List<Map<String, dynamic>> points,
);

/// Sends the driver's GPS to the API while a trip is under way.
///
/// A position stream fills a queue; every [sendEvery] the queue is flushed, oldest first,
/// together with anything an earlier failure left in sqflite. A send that fails puts the whole
/// batch back in the buffer, so a dead spot costs nothing but a gap that the next success fills.
///
/// Tracking only runs while the app is in the foreground — there is no background service.
class TrackingService {
  TrackingService._({GpsBuffer? buffer, PositionSender? sender})
    : _buffer = buffer ?? const SqfliteGpsBuffer(),
      _send =
          sender ??
          ((tripId, points) =>
              ReservationService.instance.sendPositions(tripId, points));

  static final TrackingService instance = TrackingService._();

  /// A service wired to fakes, already tracking [tripId], for the flush tests.
  @visibleForTesting
  factory TrackingService.forTest({
    required String tripId,
    required GpsBuffer buffer,
    required PositionSender sender,
  }) {
    final service = TrackingService._(buffer: buffer, sender: sender);
    service._tripId = tripId;
    return service;
  }

  /// How often the queue goes to the API.
  static const sendEvery = Duration(seconds: 4);

  /// The endpoint takes at most 50 points in one call.
  static const maxPointsPerCall = 50;

  /// Only report a new fix once the driver has moved this far.
  static const _distanceFilterM = 5;

  final GpsBuffer _buffer;
  final PositionSender _send;

  StreamSubscription<Position>? _positions;
  Timer? _timer;
  String? _tripId;

  /// Fixes recorded since the last send.
  final List<Map<String, Object?>> _queue = [];

  /// The newest LiveView the API answered with, so the screen can react without its own poll.
  final StreamController<LiveView> _views =
      StreamController<LiveView>.broadcast();
  Stream<LiveView> get views => _views.stream;

  /// Problems worth telling the driver about, such as a run of failed sends.
  final StreamController<String> _problems =
      StreamController<String>.broadcast();
  Stream<String> get problems => _problems.stream;

  bool get isTracking => _tripId != null;
  String? get trackedTripId => _tripId;

  int _consecutiveFailures = 0;

  /// Starts streaming the phone's position to [tripId]. Safe to call again for the same trip.
  Future<void> start(String tripId) async {
    if (_tripId == tripId) return;
    await stop();
    _tripId = tripId;
    _consecutiveFailures = 0;

    _positions =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: _distanceFilterM,
          ),
        ).listen(
          _record,
          onError: (_) {
            // A dropped stream must not kill tracking; the next fix re-attaches it.
          },
        );

    _timer = Timer.periodic(sendEvery, (_) => flush());

    // The stream only fires once the phone has moved [_distanceFilterM], so a driver who
    // starts while parked would send nothing at all and the passenger would sit on "waiting
    // for a position". One fix up front gives the trip a starting point — and lets the pickup
    // geofence recognise a driver who is already standing at the pickup.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (_tripId == tripId) {
        _record(first);
        await flush();
      }
    } on Exception {
      // No fix yet: the stream will deliver one as soon as the driver moves.
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _positions?.cancel();
    _positions = null;
    _tripId = null;
    _queue.clear();
  }

  void _record(Position position) => recordPoint(
    lat: position.latitude,
    lng: position.longitude,
    speedMps: position.speed.isFinite && position.speed >= 0
        ? position.speed
        : null,
    recordedAt: position.timestamp,
  );

  /// Queues one fix to go out on the next flush.
  @visibleForTesting
  void recordPoint({
    required double lat,
    required double lng,
    required DateTime recordedAt,
    double? speedMps,
  }) => _queue.add({
    'lat': lat,
    'lng': lng,
    'speedMps': speedMps,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  });

  /// Sends the buffered points plus the fresh ones, oldest first.
  @visibleForTesting
  Future<void> flush() async {
    final tripId = _tripId;
    if (tripId == null) return;

    final fresh = List<Map<String, Object?>>.from(_queue);
    _queue.clear();

    // Anything an earlier failure stored goes out ahead of the fresh fixes, so the trail the
    // server sees stays in order.
    final buffered = await _buffer.take(tripId, limit: maxPointsPerCall);
    final bufferedIds = buffered
        .map((row) => row['id']! as int)
        .toList(growable: false);
    final points = <Map<String, Object?>>[
      for (final row in buffered)
        {
          'lat': row['lat'],
          'lng': row['lng'],
          'speedMps': row['speed_mps'],
          'recordedAt': row['recorded_at'],
        },
      ...fresh,
    ];
    if (points.isEmpty) return;

    // Never send more than the endpoint accepts; the rest waits for the next tick.
    final batch = points.take(maxPointsPerCall).toList(growable: false);
    final overflow = points.skip(maxPointsPerCall).toList(growable: false);

    try {
      final view = await _send(
        tripId,
        batch.map((p) => Map<String, dynamic>.from(p)).toList(growable: false),
      );
      await _buffer.remove(bufferedIds);
      if (overflow.isNotEmpty) await _buffer.add(tripId, overflow);
      _consecutiveFailures = 0;
      if (!_views.isClosed) _views.add(view);
    } catch (_) {
      // Only the fresh points need storing. The buffered ones were never removed, and the
      // overflow is a slice of those two — adding it again would store points twice.
      await _buffer.add(tripId, fresh);
      _consecutiveFailures++;
      if (_consecutiveFailures == 3 && !_problems.isClosed) {
        _problems.add(
          'No connection — your positions are being saved and will be sent '
          'as soon as you are back online.',
        );
      }
    }
  }

  /// How many fixes are waiting to go out, for the "saved offline" badge.
  Future<int> pendingCount(String tripId) => _buffer.count(tripId);
}
