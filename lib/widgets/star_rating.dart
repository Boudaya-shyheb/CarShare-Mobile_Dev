import 'package:flutter/material.dart';

import '../theme.dart';
import 'trip_formats.dart';

/// "★ 4.8 · 12 ratings", or "New driver" when nobody has rated them yet.
class RatingLine extends StatelessWidget {
  const RatingLine({
    super.key,
    required this.average,
    required this.count,
    this.emptyLabel = 'New driver',
  });

  final double? average;
  final int count;

  /// What to say with no ratings at all — "New driver" or "New passenger".
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final rated = average != null && count > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rated) ...[
          const Icon(Icons.star_rounded, size: 16, color: carShareWarning),
          const SizedBox(width: 3),
        ],
        Text(
          rated ? formatRating(average, count) : emptyLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: carShareMuted),
        ),
      ],
    );
  }
}

/// Five stars the user taps to score somebody, 1–5. Read-only when [onChanged] is null.
class StarPicker extends StatelessWidget {
  const StarPicker({
    super.key,
    required this.stars,
    this.onChanged,
    this.size = 40,
  });

  final int stars;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var star = 1; star <= 5; star++)
        Semantics(
          button: onChanged != null,
          label: '$star star${star == 1 ? '' : 's'}',
          child: InkResponse(
            radius: size * 0.6,
            onTap: onChanged == null ? null : () => onChanged!(star),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                star <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: star <= stars ? carShareWarning : carShareBorder,
              ),
            ),
          ),
        ),
    ],
  );
}
