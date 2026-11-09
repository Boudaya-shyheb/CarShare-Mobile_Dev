import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/rating.dart';
import '../../models/trip.dart';
import '../../models/trip_event.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/live_widgets.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/trip_formats.dart';

/// The completion screen as a page of its own, for opening a finished trip from My trips.
///
/// The live screens render [TripCompletedView] inline instead, because they already hold the
/// trip and are showing it in place of the map.
class TripCompletedPage extends StatelessWidget {
  const TripCompletedPage({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: carShareBackground,
      surfaceTintColor: carShareBackground,
      title: const Text(
        'Trip summary',
        style: TextStyle(fontWeight: FontWeight.w700, color: carShareText),
      ),
    ),
    body: FutureBuilder<Trip>(
      future: ReservationService.instance.trip(tripId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                authErrorMessage(snapshot.error ?? 'unknown'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: carShareMuted, height: 1.4),
              ),
            ),
          );
        }
        return TripCompletedView(
          trip: snapshot.data!,
          onDone: () => Navigator.of(context).pop(),
        );
      },
    ),
  );
}

/// Mockup 11 — what both sides see once the trip is over.
///
/// The planned route is drawn dashed and grey, the track the car actually drove in green, and
/// "Replay trip" walks a marker along that track. Below it: the trip's own stats, the timeline
/// straight out of the audit trail, and a star rating for each person who shared the trip.
class TripCompletedView extends StatefulWidget {
  const TripCompletedView({
    super.key,
    required this.trip,
    required this.onDone,
    this.arrivedAt,
  });

  final Trip trip;
  final VoidCallback onDone;

  /// When the trip actually finished; falls back to its expected arrival.
  final DateTime? arrivedAt;

  @override
  State<TripCompletedView> createState() => _TripCompletedViewState();
}

class _TripCompletedViewState extends State<TripCompletedView>
    with SingleTickerProviderStateMixin {
  /// How long the replay takes, whatever the length of the trip.
  static const _replayDuration = Duration(seconds: 8);

  late final AnimationController _replay = AnimationController(
    vsync: this,
    duration: _replayDuration,
  )..addListener(() => setState(() {}));

  late Future<_Aftermath> _data = _load();

  @override
  void dispose() {
    _replay.dispose();
    super.dispose();
  }

  Future<_Aftermath> _load() async {
    final tripId = widget.trip.id;
    // The three calls are independent, so they go out together rather than one after another.
    final results = await Future.wait([
      ReservationService.instance.trackPoints(tripId),
      ReservationService.instance
          .tripEvents(tripId)
          .catchError(
            // A passenger may not read the driver's audit trail; the timeline is then just absent.
            (_) => <TripEvent>[],
          ),
      ReservationService.instance.myRatings(tripId),
    ]);
    return _Aftermath(
      track: (results[0] as List<TrackPoint>)
          .map((point) => LatLng(point.lat, point.lng))
          .toList(growable: false),
      events: results[1] as List<TripEvent>,
      ratings: results[2] as MyRatings,
    );
  }

  void _reload() => setState(() {
    _data = _load();
  });

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FutureBuilder<_Aftermath>(
            future: _data,
            builder: (context, snapshot) {
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              // The live screens know when the car arrived. Opened later from My trips there
              // is no such value, so the COMPLETED event says it; only a trip with neither
              // falls back to departure plus the planned duration.
              final completedAt = snapshot.hasData
                  ? snapshot.data!.events
                        .where((event) => event.type == 'COMPLETED')
                        .map((event) => event.createdAt)
                        .fold<DateTime?>(null, (_, at) => at)
                  : null;
              final when =
                  widget.arrivedAt ??
                  completedAt ??
                  trip.departureTime.add(
                    Duration(seconds: trip.durationS ?? 2 * 60 * 60),
                  );
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: [
                    _buildHeader(trip, when),
                    const SizedBox(height: 22),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(),
                      )
                    else if (snapshot.hasError)
                      _buildProblem(authErrorMessage(snapshot.error!))
                    else ...[
                      _buildReplay(trip, snapshot.data!.track),
                      const SizedBox(height: 18),
                      _buildStats(trip),
                      const SizedBox(height: 18),
                      if (snapshot.data!.events.isNotEmpty)
                        _TripTimeline(events: snapshot.data!.events),
                      if (snapshot.data!.events.isNotEmpty)
                        const SizedBox(height: 18),
                      _buildRatings(snapshot.data!.ratings),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: carShareButtonHeight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              carShareButtonRadius,
                            ),
                          ),
                        ),
                        onPressed: widget.onDone,
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Trip trip, DateTime when) => Column(
    children: [
      Container(
        width: 118,
        height: 118,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: carShareTint,
          shape: BoxShape.circle,
        ),
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: carShareGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 42, color: Colors.white),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        "You've arrived!",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: carShareText,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${trip.destinationLabel} · ${formatClock(when)}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, color: carShareMuted),
      ),
    ],
  );

  Widget _buildProblem(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: carShareMuted, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: _reload, child: const Text('Try again')),
      ],
    ),
  );

  Widget _buildReplay(Trip trip, List<LatLng> track) {
    final planned = GeoService.instance
        .decodePolyline(trip.routePolyline)
        .map((p) => LatLng(p[0], p[1]))
        .toList(growable: false);
    if (track.length < 2 && planned.length < 2) {
      return _buildNoTrack();
    }
    final frame = track.isNotEmpty ? track : planned;
    final marker = track.isEmpty ? null : _pointAt(track, _replay.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(carShareCardRadius),
          child: SizedBox(
            height: 230,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(frame),
                      padding: const EdgeInsets.all(34),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.carshare.app',
                    ),
                    // The plan underneath, grey and dashed; what really happened on top.
                    if (planned.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: planned,
                            strokeWidth: 4,
                            color: carShareMuted.withValues(alpha: 0.55),
                            pattern: StrokePattern.dashed(
                              segments: const [8, 6],
                            ),
                          ),
                        ],
                      ),
                    if (track.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: track,
                            strokeWidth: 5,
                            color: carShareGreen,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (track.isNotEmpty)
                          Marker(
                            point: track.first,
                            width: 24,
                            height: 24,
                            child: const TripEndDot(square: false),
                          ),
                        if (track.length > 1)
                          Marker(
                            point: track.last,
                            width: 24,
                            height: 24,
                            child: const TripEndDot(square: true),
                          ),
                        if (marker != null)
                          Marker(
                            point: marker,
                            width: 42,
                            height: 42,
                            child: const _ReplayCar(),
                          ),
                      ],
                    ),
                  ],
                ),
                if (track.length > 1)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _ReplayButton(
                      running: _replay.isAnimating,
                      onTap: () {
                        if (_replay.isAnimating) {
                          _replay.stop();
                        } else {
                          _replay.forward(from: 0);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (track.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'No GPS trail was recorded for this trip, so only the planned '
            'route is shown.',
            style: TextStyle(fontSize: 12, color: carShareMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildNoTrack() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(carShareCardRadius),
      border: Border.all(color: carShareBorder),
    ),
    child: const Row(
      children: [
        Icon(Icons.map_outlined, color: carShareMuted),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'There is no map for this trip: no route was planned and no '
            'positions were recorded.',
            style: TextStyle(fontSize: 13, color: carShareMuted, height: 1.3),
          ),
        ),
      ],
    ),
  );

  /// Where the replay marker sits at [t] (0..1) along the track, by point index.
  static LatLng _pointAt(List<LatLng> track, double t) {
    if (track.length == 1) return track.first;
    final exact = t * (track.length - 1);
    final index = exact.floor().clamp(0, track.length - 2);
    final from = track[index];
    final to = track[index + 1];
    final step = exact - index;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * step,
      from.longitude + (to.longitude - from.longitude) * step,
    );
  }

  Widget _buildStats(Trip trip) => Row(
    children: [
      _Stat(
        value: trip.distanceM == null ? '—' : formatDistance(trip.distanceM!),
        caption: 'Distance',
      ),
      const SizedBox(width: 12),
      _Stat(value: formatDuration(trip.durationS), caption: 'Duration'),
    ],
  );

  Widget _buildRatings(MyRatings ratings) {
    if (!ratings.tripCompleted || ratings.parties.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ratings.parties.length == 1
              ? 'Rate ${ratings.parties.first.name}'
              : 'Rate your passengers',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
        const SizedBox(height: 10),
        for (final party in ratings.parties)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RatingRow(
              tripId: widget.trip.id,
              party: party,
              onSaved: _reload,
            ),
          ),
      ],
    );
  }
}

/// Everything the screen needs about a finished trip, fetched in one go.
class _Aftermath {
  const _Aftermath({
    required this.track,
    required this.events,
    required this.ratings,
  });

  final List<LatLng> track;
  final List<TripEvent> events;
  final MyRatings ratings;
}

class _ReplayCar extends StatelessWidget {
  const _ReplayCar();

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.directions_car_filled,
      size: 22,
      color: carShareGreen,
    ),
  );
}

class _ReplayButton extends StatelessWidget {
  const _ReplayButton({required this.running, required this.onTap});

  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: carShareText,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              running ? 'Pause' : 'Replay trip',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The audit trail, in words: what happened and when.
class _TripTimeline extends StatelessWidget {
  const _TripTimeline({required this.events});

  final List<TripEvent> events;

  /// Only the events worth showing a human; the reservation bookkeeping is left out.
  static const _labels = <String, String>{
    'PUBLISHED': 'Trip published',
    'DRIVER_EN_ROUTE': 'Driver set off',
    'DRIVER_ARRIVED': 'Driver arrived · inside pickup zone',
    'CHECK_IN': 'Pickup confirmed',
    'NO_SHOW': 'Passenger marked as a no-show',
    'PICKED_UP': 'Everyone aboard',
    'IN_PROGRESS': 'Ride started',
    'DEVIATION': 'Route deviation',
    'DEVIATION_RESOLVED': 'Back on the planned route',
    'COMPLETED': 'Trip completed · drop-off zone',
    'CANCELLED': 'Trip cancelled',
  };

  static Color _colourFor(String type) => switch (type) {
    'DEVIATION' => carShareWarning,
    'NO_SHOW' || 'CANCELLED' => carShareDanger,
    _ => carShareSuccess,
  };

  @override
  Widget build(BuildContext context) {
    final shown = events
        .where((event) => _labels.containsKey(event.type))
        .toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(carShareCardRadius),
        border: Border.all(color: carShareBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip timeline',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 12),
          for (final event in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      formatClock(event.createdAt),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: carShareMuted,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 10),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colourFor(event.type),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _labels[event.type]!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: carShareText,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One person to rate: stars, an optional comment, and Submit — or "Rated" once it is in.
class _RatingRow extends StatefulWidget {
  const _RatingRow({
    required this.tripId,
    required this.party,
    required this.onSaved,
  });

  final String tripId;
  final RatableParty party;
  final VoidCallback onSaved;

  @override
  State<_RatingRow> createState() => _RatingRowState();
}

class _RatingRowState extends State<_RatingRow> {
  late int _stars = widget.party.myRating?.stars ?? 0;
  late final TextEditingController _comment = TextEditingController(
    text: widget.party.myRating?.comment ?? '',
  );
  late bool _editing = widget.party.myRating == null;
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap a star to give a score first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final comment = _comment.text.trim();
      final service = ReservationService.instance;
      // The same form both leaves a rating and changes one, so which call depends on whether
      // anything is there yet; the server owns the 24 h window either way.
      if (widget.party.myRating == null) {
        await service.rate(
          widget.tripId,
          toUserId: widget.party.userId,
          stars: _stars,
          comment: comment.isEmpty ? null : comment,
        );
      } else {
        await service.reviseRating(
          widget.tripId,
          toUserId: widget.party.userId,
          stars: _stars,
          comment: comment.isEmpty ? null : comment,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: carShareSuccess,
          content: Text('Thanks — ${widget.party.name} has been rated.'),
        ),
      );
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.party.myRating;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(carShareCardRadius),
        border: Border.all(color: carShareBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.party.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
              ),
              if (existing != null && !_editing)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: carShareSuccess,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Rated',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: carShareSuccess,
                      ),
                    ),
                    if (existing.editable)
                      TextButton(
                        onPressed: () => setState(() => _editing = true),
                        child: const Text('Change'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          StarPicker(
            stars: _stars,
            size: 34,
            onChanged: _editing && !_saving
                ? (value) => setState(() => _stars = value)
                : null,
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Add a comment (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(existing == null ? 'Submit' : 'Save change'),
              ),
            ),
          ] else if (existing?.comment != null) ...[
            const SizedBox(height: 8),
            Text(
              existing!.comment!,
              style: const TextStyle(
                fontSize: 13,
                color: carShareMuted,
                height: 1.3,
              ),
            ),
          ],
          if (existing != null && !existing.editable && !_editing) ...[
            const SizedBox(height: 6),
            const Text(
              'Ratings can no longer be changed after 24 hours.',
              style: TextStyle(fontSize: 12, color: carShareMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(fontSize: 13, color: carShareMuted),
          ),
        ],
      ),
    ),
  );
}
