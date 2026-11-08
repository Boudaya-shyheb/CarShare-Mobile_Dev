import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/place.dart';
import '../../theme.dart';

/// Placeholder for the matching results list (mockup 05), which arrives in step 8.
///
/// It already receives the whole search, so step 8 only has to swap this body for the call to
/// `ReservationService.searchTrips` and the result cards.
class SearchResultsPage extends StatelessWidget {
  const SearchResultsPage({
    super.key,
    required this.from,
    required this.to,
    required this.departureTime,
    required this.seats,
  });

  final Place from;
  final Place to;
  final DateTime departureTime;
  final int seats;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Text(
        'Matching rides',
        style: TextStyle(fontWeight: FontWeight.w700, color: carShareText),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(carShareCardRadius),
                    border: Border.all(color: carShareBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(label: 'FROM', value: from.label),
                      const SizedBox(height: 14),
                      _Line(label: 'TO', value: to.label),
                      const SizedBox(height: 14),
                      _Line(
                        label: 'WHEN',
                        value: DateFormat('EEEE d MMMM, HH:mm')
                            .format(departureTime),
                      ),
                      const SizedBox(height: 14),
                      _Line(
                        label: 'SEATS',
                        value: seats == 1 ? '1 seat' : '$seats seats',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: carShareTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.travel_explore,
                          size: 34,
                          color: carShareGreen,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'The matching list lands in step 8.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: carShareMuted),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'These are the parameters it will search with.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: carShareMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: carShareMuted,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: carShareText,
        ),
      ),
    ],
  );
}
