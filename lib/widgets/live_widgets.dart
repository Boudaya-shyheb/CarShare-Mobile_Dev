import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

/// The pieces mockups 08 and 10 share between the passenger's and the driver's live screens.

/// The planned route, the two ends, and the car where it was last seen.
class LiveMap extends StatelessWidget {
  const LiveMap({
    super.key,
    required this.route,
    required this.pickup,
    required this.dropoff,
    this.car,
    this.target,
    this.controller,
  });

  /// The decoded `routePolyline`; empty when the trip was published without one.
  final List<LatLng> route;
  final LatLng pickup;
  final LatLng dropoff;

  /// The driver's last reported position; null until the first fix arrives.
  final LatLng? car;

  /// Where the car is heading — the pickup, then the drop-off. The camera frames the car and
  /// this point rather than the whole route: on a 150 km trip, fitting the route shrinks the
  /// car to a speck and the screen stops being live.
  final LatLng? target;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final here = car;
    final heading = target;
    final framed = here != null && heading != null
        ? <LatLng>[here, heading]
        : <LatLng>[pickup, dropoff, ...route, ?car];

    // Once the car reaches its target the two points coincide, and a zero-size bounds gives
    // CameraFit nothing to work with — the map comes out blank. Centre on the car instead.
    final degenerate =
        framed.length < 2 ||
        (_spread(framed, (p) => p.latitude) < 0.0005 &&
            _spread(framed, (p) => p.longitude) < 0.0005);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: degenerate ? framed.first : const LatLng(0, 0),
        initialZoom: degenerate ? 16 : 13,
        initialCameraFit: degenerate
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(framed),
                // The bottom inset clears the sheet, which covers roughly half the screen:
                // without it the target sits behind the sheet and the frame looks wrong.
                padding: const EdgeInsets.fromLTRB(56, 120, 56, 380),
              ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.carshare.app',
        ),
        if (route.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 5, color: carShareGreen),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: pickup,
              width: 26,
              height: 26,
              child: const TripEndDot(square: false),
            ),
            Marker(
              point: dropoff,
              width: 26,
              height: 26,
              child: const TripEndDot(square: true),
            ),
            if (car != null)
              Marker(
                point: car!,
                width: 52,
                height: 52,
                child: const _CarMarker(),
              ),
          ],
        ),
      ],
    );
  }
}

/// How far apart the framed points are on one axis.
double _spread(List<LatLng> points, double Function(LatLng) of) {
  var low = of(points.first);
  var high = low;
  for (final point in points) {
    final value = of(point);
    if (value < low) low = value;
    if (value > high) high = value;
  }
  return high - low;
}

class _CarMarker extends StatelessWidget {
  const _CarMarker();

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10)],
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.directions_car_filled,
      size: 26,
      color: carShareGreen,
    ),
  );
}

/// A round pickup dot or a square drop-off marker, on a white disc so it reads on any tile.
class TripEndDot extends StatelessWidget {
  const TripEndDot({super.key, required this.square});

  final bool square;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(7) : null,
      boxShadow: const [carShareCardShadow],
    ),
    padding: const EdgeInsets.all(5),
    child: Container(
      decoration: BoxDecoration(
        color: square ? const Color(0xFF065F46) : carShareSuccess,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(4) : null,
      ),
    ),
  );
}

/// The floating "Driver en route" pill at the top of the live map.
class LiveStatusPill extends StatelessWidget {
  const LiveStatusPill({super.key, required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      boxShadow: const [carShareCardShadow],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: carShareText,
          ),
        ),
      ],
    ),
  );
}

/// Scheduled · En route · Arrived · Picked up · Done, with everything reached so far in green.
class TripStatusStepper extends StatelessWidget {
  const TripStatusStepper({super.key, required this.tripStatus});

  final String tripStatus;

  static const _steps = [
    'Scheduled',
    'En route',
    'Arrived',
    'Picked up',
    'Done',
  ];

  /// IN_PROGRESS shares the "Picked up" step: both mean everyone is aboard and moving.
  static int indexFor(String status) => switch (status) {
    'SCHEDULED' => 0,
    'DRIVER_EN_ROUTE' => 1,
    'DRIVER_ARRIVED' => 2,
    'PICKED_UP' || 'IN_PROGRESS' => 3,
    'COMPLETED' => 4,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final current = indexFor(tripStatus);
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 22),
                color: i <= current ? carShareGreen : carShareBorder,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Node(done: i < current, active: i == current),
              const SizedBox(height: 6),
              SizedBox(
                width: 62,
                child: Text(
                  _steps[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i <= current
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: i <= current ? carShareGreen : carShareMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: carShareGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
    }
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? carShareGreen : carShareBorder,
          width: 2,
        ),
      ),
      child: active
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: carShareGreen,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// Mockup 10's orange alert. "I'm OK" only hides it on this device — the server keeps its own
/// `deviating` flag, and the card returns if the driver is still off route after it clears.
class DeviationCard extends StatelessWidget {
  const DeviationCard({super.key, required this.onDismiss, this.offRouteM});

  final VoidCallback onDismiss;
  final int? offRouteM;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: carShareWarning, width: 2),
      boxShadow: const [carShareCardShadow],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: carShareWarning.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: carShareWarning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Route deviation detected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: carShareText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offRouteM == null
                        ? 'The car is off the planned route.'
                        : 'Driver is $offRouteM m off the planned route.',
                    style: const TextStyle(fontSize: 13, color: carShareMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onDismiss,
            child: const Text("I'm OK"),
          ),
        ),
      ],
    ),
  );
}
