import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/trip_search_result.dart';
import '../theme.dart';
import 'trip_formats.dart';

/// Client-side filters on the search results that are already on screen. Nothing here goes to
/// the server: the list is only narrowed, never searched again.
@immutable
class ResultFilters {
  const ResultFilters({
    this.maxPrice,
    this.minSeats = 1,
    this.instantOnly = false,
    this.minRating,
  });

  /// No filter at all.
  static const none = ResultFilters();

  /// Most a seat may cost, in dinars. Null means any price.
  final double? maxPrice;

  /// Fewest free seats a trip must have. 1 is no filter: a result always has at least one.
  final int minSeats;
  final bool instantOnly;

  /// Lowest driver rating accepted. Null means any; a driver with no rating yet is left out
  /// as soon as this is set.
  final double? minRating;

  /// How many of the four filters are doing something: the number on the icon.
  int get activeCount =>
      (maxPrice != null ? 1 : 0) +
      (minSeats > 1 ? 1 : 0) +
      (instantOnly ? 1 : 0) +
      (minRating != null ? 1 : 0);

  bool get isActive => activeCount > 0;

  bool matches(TripSearchResult result) {
    if (maxPrice != null && result.pricePerSeat > maxPrice!) return false;
    if (result.seatsAvailable < minSeats) return false;
    if (instantOnly && !result.instantBooking) return false;
    if (minRating != null) {
      final rating = result.driverRating;
      if (rating == null || rating < minRating!) return false;
    }
    return true;
  }

  List<TripSearchResult> apply(List<TripSearchResult> results) =>
      results.where(matches).toList(growable: false);

  ResultFilters copyWith({
    double? maxPrice,
    bool clearMaxPrice = false,
    int? minSeats,
    bool? instantOnly,
    double? minRating,
    bool clearMinRating = false,
  }) => ResultFilters(
    maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
    minSeats: minSeats ?? this.minSeats,
    instantOnly: instantOnly ?? this.instantOnly,
    minRating: clearMinRating ? null : (minRating ?? this.minRating),
  );

  @override
  bool operator ==(Object other) =>
      other is ResultFilters &&
      other.maxPrice == maxPrice &&
      other.minSeats == minSeats &&
      other.instantOnly == instantOnly &&
      other.minRating == minRating;

  @override
  int get hashCode => Object.hash(maxPrice, minSeats, instantOnly, minRating);
}

/// Opens the filters sheet. Returns the filters to use, or null if it was dismissed.
/// [results] are the unfiltered results, which set the top of the price slider.
Future<ResultFilters?> showResultFiltersSheet(
  BuildContext context, {
  required ResultFilters current,
  required List<TripSearchResult> results,
}) {
  final top = results.isEmpty
      ? 50.0
      : math.max(
          1.0,
          results.map((r) => r.pricePerSeat).reduce(math.max).ceilToDouble(),
        );
  return showModalBottomSheet<ResultFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FiltersSheet(current: current, priceTop: top),
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.current, required this.priceTop});

  final ResultFilters current;
  final double priceTop;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late ResultFilters _draft = widget.current;

  @override
  Widget build(BuildContext context) {
    final price = (_draft.maxPrice ?? widget.priceTop).clamp(
      0.0,
      widget.priceTop,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: carShareText,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _draft.isActive
                        ? () => setState(() => _draft = ResultFilters.none)
                        : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Label(
                'Max price per seat',
                trailing: _draft.maxPrice == null
                    ? 'Any'
                    : formatPrice(_draft.maxPrice!),
              ),
              Slider(
                value: price.toDouble(),
                max: widget.priceTop,
                divisions: widget.priceTop.round().clamp(1, 100),
                label: formatPrice(price.toDouble()),
                onChanged: (value) => setState(
                  () => _draft = value >= widget.priceTop
                      ? _draft.copyWith(clearMaxPrice: true)
                      : _draft.copyWith(maxPrice: value),
                ),
              ),
              const SizedBox(height: 8),
              const _Label('Free seats'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final seats in const [1, 2, 3, 4])
                    ChoiceChip(
                      label: Text(seats == 1 ? 'Any' : '$seats+'),
                      selected: _draft.minSeats == seats,
                      onSelected: (_) => setState(
                        () => _draft = _draft.copyWith(minSeats: seats),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _Label('Driver rating'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final rating in const <double?>[null, 3.0, 4.0, 4.5])
                    ChoiceChip(
                      label: Text(rating == null ? 'Any' : '$rating+ ★'),
                      selected: _draft.minRating == rating,
                      onSelected: (_) => setState(
                        () => _draft = rating == null
                            ? _draft.copyWith(clearMinRating: true)
                            : _draft.copyWith(minRating: rating),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: carShareGreen,
                value: _draft.instantOnly,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(instantOnly: value),
                ),
                title: const Text(
                  'Instant booking only',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: carShareText,
                  ),
                ),
                subtitle: const Text(
                  'Seats confirmed without waiting for the driver.',
                  style: TextStyle(fontSize: 12, color: carShareMuted),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: carShareButtonHeight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: const Text(
                    'Show trips',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: carShareText,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: carShareGreen,
          ),
        ),
    ],
  );
}
