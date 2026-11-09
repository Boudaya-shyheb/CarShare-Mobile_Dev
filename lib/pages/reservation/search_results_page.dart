import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../../models/trip_search_result.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/route_title.dart';
import '../../widgets/trip_formats.dart';
import '../../widgets/trip_result_card.dart';
import 'trip_details_page.dart';

/// Mockup 05 — the trips that match the search, ordered by the chosen sort.
class SearchResultsPage extends StatefulWidget {
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
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  static const _sorts = {
    'best': 'Best match',
    'cheapest': 'Cheapest',
    'earliest': 'Earliest',
  };

  String _sort = 'best';
  late Future<List<TripSearchResult>> _results = _search();

  Future<List<TripSearchResult>> _search() =>
      ReservationService.instance.searchTrips(
        originLat: widget.from.lat,
        originLng: widget.from.lng,
        destinationLat: widget.to.lat,
        destinationLng: widget.to.lng,
        departureTime: widget.departureTime,
        seats: widget.seats,
        sort: _sort,
      );

  void _changeSort(String sort) {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      _results = _search();
    });
  }

  void _retry() => setState(() {
    _results = _search();
  });

  Future<void> _openTrip(TripSearchResult result) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TripDetailsPage(
          tripId: result.tripId,
          matchScore: result.matchScore,
          seatsWanted: widget.seats,
        ),
      ),
    );
    // A booking takes seats off this trip, so the list behind it is already out of date.
    if (booked == true && mounted) _retry();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildSortChips(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: carShareText),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RouteTitle(
                origin: widget.from.shortLabel,
                destination: widget.to.shortLabel,
              ),
              const SizedBox(height: 2),
              Text(
                '${formatWhen(widget.departureTime)} · '
                '${formatSeats(widget.seats)}',
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.tune, color: carShareText),
          tooltip: 'Filters',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Filters arrive in a later step.')),
          ),
        ),
      ],
    ),
  );

  Widget _buildSortChips() => SizedBox(
    height: 56,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final entry in _sorts.entries)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _SortChip(
              label: entry.value,
              selected: _sort == entry.key,
              onTap: () => _changeSort(entry.key),
            ),
          ),
      ],
    ),
  );

  Widget _buildBody() => FutureBuilder<List<TripSearchResult>>(
    future: _results,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _Message(
          icon: Icons.cloud_off,
          title: 'The search did not go through',
          line: authErrorMessage(snapshot.error!),
          action: FilledButton(onPressed: _retry, child: const Text('Retry')),
        );
      }
      final results = snapshot.data ?? const <TripSearchResult>[];
      if (results.isEmpty) {
        return const _Message(
          icon: Icons.search_off,
          title: 'No driver matches this trip yet',
          line:
              'Try a different time, or widen the search by picking a '
              'pick-up point closer to a main road.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LiveBanner(count: results.length),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: results.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TripResultCard(
                  result: results[index],
                  onTap: () => _openTrip(results[index]),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: selected ? carShareGreen : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? carShareGreen : carShareBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : carShareText,
        ),
      ),
    ),
  );
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: carShareTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: carShareGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live matching · $count '
              '${count == 1 ? 'driver' : 'drivers'} found',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: carShareGreen,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.line,
    this.action,
  });

  final IconData icon;
  final String title;
  final String line;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: carShareTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: carShareGreen),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
