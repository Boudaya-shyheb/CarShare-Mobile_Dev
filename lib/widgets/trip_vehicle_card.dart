import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/trip_vehicle.dart';
import '../services/reservation_service.dart';
import '../theme.dart';

/// The car on a trip: photo, brand and model, colour, plate (when the viewer may see it) and
/// seats. Loads `GET /trips/{id}/vehicle` itself, so any screen that knows a trip id can drop it
/// in. [trailing] sits at the end of the title row, for a chip such as "Instant".
class TripVehicleCard extends StatefulWidget {
  const TripVehicleCard({super.key, required this.tripId, this.trailing});

  final String tripId;
  final Widget? trailing;

  @override
  State<TripVehicleCard> createState() => _TripVehicleCardState();
}

class _TripVehicleCardState extends State<TripVehicleCard> {
  late final Future<_Loaded> _loaded = _load();

  Future<_Loaded> _load() async {
    final vehicle = await ReservationService.instance.tripVehicle(
      widget.tripId,
    );
    Uint8List? photo;
    if (vehicle.hasPhoto) {
      try {
        photo = await ReservationService.instance.tripVehiclePhoto(
          widget.tripId,
        );
      } catch (_) {
        photo = null; // the details still show without the picture
      }
    }
    return _Loaded(vehicle, photo);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Loaded>(
    future: _loaded,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _CardShell(
          child: SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      }
      if (snapshot.hasError || snapshot.data == null) {
        // Trips published before vehicles were required have no car on record.
        return _CardShell(
          child: Row(
            children: [
              const Icon(Icons.directions_car_outlined, color: carShareMuted),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No vehicle on record for this trip.',
                  style: TextStyle(color: carShareMuted),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        );
      }
      final data = snapshot.data!;
      final vehicle = data.vehicle;
      return _CardShell(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.photo != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Image.memory(
                  data.photo!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo of ${vehicle.title}',
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (data.photo == null) ...[
                        const Icon(
                          Icons.directions_car_outlined,
                          color: carShareGreen,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          '${vehicle.title} · ${vehicle.year}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: carShareText,
                          ),
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Fact(icon: Icons.palette_outlined, text: vehicle.color),
                      if (vehicle.registrationNumber != null)
                        _Fact(
                          icon: Icons.confirmation_number_outlined,
                          text: vehicle.registrationNumber!,
                        ),
                      _Fact(
                        icon: Icons.event_seat_outlined,
                        text: '${vehicle.seatsNumber} seats',
                      ),
                      if (vehicle.airConditioning)
                        const _Fact(icon: Icons.ac_unit, text: 'A/C'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Loaded {
  const _Loaded(this.vehicle, this.photo);
  final TripVehicle vehicle;
  final Uint8List? photo;
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: carShareBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: carShareMuted),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: carShareText,
          ),
        ),
      ],
    ),
  );
}
