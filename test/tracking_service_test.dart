import 'package:carshare/models/live_view.dart';
import 'package:carshare/services/tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offline buffer: what happens to the driver's fixes when a send fails.
///
/// These run without a device. [_FakeBuffer] stands in for sqflite and keeps the same contract
/// — rows with ascending ids, oldest first — so the order the service relies on is the order
/// the real table gives it.
void main() {
  late _FakeBuffer buffer;
  late _FakeSender sender;
  late TrackingService service;

  const tripId = 'trip-1';
  final start = DateTime.utc(2026, 11, 21, 7);

  setUp(() {
    buffer = _FakeBuffer();
    sender = _FakeSender();
    service = TrackingService.forTest(
      tripId: tripId,
      buffer: buffer,
      sender: sender.send,
    );
  });

  void record(int second) => service.recordPoint(
    lat: 36.80 + second / 10000,
    lng: 10.18,
    recordedAt: start.add(Duration(seconds: second)),
  );

  /// The recordedAt seconds of a batch, which is how each point is identified here.
  List<int> secondsOf(List<Map<String, dynamic>> batch) => batch
      .map(
        (point) =>
            DateTime.parse(point['recordedAt']! as String)
                .difference(start)
                .inSeconds,
      )
      .toList(growable: false);

  test(
    'a successful send empties the queue and leaves nothing buffered',
    () async {
      record(0);
      record(4);

      await service.flush();

      expect(sender.batches, hasLength(1));
      expect(secondsOf(sender.batches.single), [0, 4]);
      expect(buffer.rows, isEmpty);
    },
  );

  test(
    'a failed send keeps the points, in order, instead of losing them',
    () async {
      sender.failNext = true;
      record(0);
      record(4);
      record(8);

      await service.flush();

      expect(buffer.rows.map((row) => row['lat']), hasLength(3));
      expect(
        buffer.rows
            .map(
              (row) =>
                  DateTime.parse(row['recorded_at']! as String)
                      .difference(start)
                      .inSeconds,
            )
            .toList(),
        [0, 4, 8],
        reason:
            'the buffer has to preserve the order the phone recorded them in',
      );
      expect(await service.pendingCount(tripId), 3);
    },
  );

  test(
    'the next success flushes the buffer first, then the fresh fixes',
    () async {
      sender.failNext = true;
      record(0);
      record(4);
      await service.flush();
      expect(sender.batches, isEmpty, reason: 'the first attempt failed');

      record(8);
      await service.flush();

      expect(sender.batches, hasLength(1));
      expect(secondsOf(sender.batches.single), [
        0,
        4,
        8,
      ], reason: 'buffered points go out ahead of the ones recorded since');
      expect(
        buffer.rows,
        isEmpty,
        reason: 'the buffer is cleared once accepted',
      );
      expect(await service.pendingCount(tripId), 0);
    },
  );

  test('a batch never exceeds the 50 points the endpoint accepts', () async {
    sender.failNext = true;
    for (var i = 0; i < 60; i++) {
      record(i * 4);
    }
    await service.flush();
    expect(await service.pendingCount(tripId), 60);

    await service.flush();

    expect(sender.batches.single, hasLength(TrackingService.maxPointsPerCall));
    expect(secondsOf(sender.batches.single).first, 0);
    expect(secondsOf(sender.batches.single).last, 49 * 4);
    expect(
      await service.pendingCount(tripId),
      10,
      reason: 'the ten that did not fit wait for the next tick',
    );

    await service.flush();

    expect(sender.batches, hasLength(2));
    expect(secondsOf(sender.batches.last), [
      for (var i = 50; i < 60; i++) i * 4,
    ]);
    expect(await service.pendingCount(tripId), 0);
  });

  test('a point is sent once and once only', () async {
    sender.failNext = true;
    record(0);
    await service.flush();

    await service.flush();
    await service.flush();

    final sent = sender.batches.expand(secondsOf).toList();
    expect(sent, [
      0,
    ], reason: 'the second flush must not resend what was accepted');
  });

  test('flushing with nothing to send does not call the API at all', () async {
    await service.flush();

    expect(sender.batches, isEmpty);
  });
}

/// An in-memory stand-in for the sqflite table, with the same ascending-id ordering.
class _FakeBuffer implements GpsBuffer {
  final List<Map<String, Object?>> rows = [];
  int _nextId = 1;

  @override
  Future<void> add(String tripId, List<Map<String, Object?>> points) async {
    for (final point in points) {
      rows.add({
        'id': _nextId++,
        'trip_id': tripId,
        'lat': point['lat'],
        'lng': point['lng'],
        'speed_mps': point['speedMps'],
        'recorded_at': point['recordedAt'],
      });
    }
  }

  @override
  Future<List<Map<String, Object?>>> take(
    String tripId, {
    int limit = 50,
  }) async =>
      rows.where((row) => row['trip_id'] == tripId).take(limit).toList();

  @override
  Future<void> remove(List<int> ids) async =>
      rows.removeWhere((row) => ids.contains(row['id']));

  @override
  Future<int> count(String tripId) async =>
      rows.where((row) => row['trip_id'] == tripId).length;
}

/// Records every batch it is given, and can be told to refuse the next one.
class _FakeSender {
  final List<List<Map<String, dynamic>>> batches = [];
  bool failNext = false;

  Future<LiveView> send(
    String tripId,
    List<Map<String, dynamic>> points,
  ) async {
    if (failNext) {
      failNext = false;
      throw Exception('no connection');
    }
    batches.add(points);
    return LiveView.fromJson(const {
      'tripStatus': 'IN_PROGRESS',
      'target': 'DROPOFF',
      'deviating': false,
    });
  }
}
