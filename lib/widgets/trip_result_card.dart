import 'package:flutter/material.dart';

import '../models/trip_search_result.dart';
import '../theme.dart';
import 'star_rating.dart';
import 'status_chip.dart';
import 'trip_formats.dart';

/// One row of the matching results list (mockup 05).
class TripResultCard extends StatelessWidget {
  const TripResultCard({super.key, required this.result, required this.onTap});

  final TripSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CarShareCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(initials: initialsOf(result.driverName)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.driverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: carShareText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      RatingLine(
                        average: result.driverRating,
                        count: result.driverRatingCount,
                      ),
                      const Text(
                        '  ·  ',
                        style: TextStyle(fontSize: 13, color: carShareMuted),
                      ),
                      Flexible(
                        child: Text(
                          result.instantBooking ? 'Instant' : 'Confirms',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: carShareMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(
              label: '${result.matchScore}% match',
              colour: carShareGreen,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: carShareBorder),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${formatClock(result.departureTime)} → '
                        '${formatClock(result.expectedArrival)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: carShareText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDayLabel(result.departureTime),
                        style: const TextStyle(
                          fontSize: 13,
                          color: carShareMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatSeats(result.seatsAvailable)} left · '
                    '${formatDistance(result.pickupDistanceM)} from you',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: carShareMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatPrice(result.pricePerSeat),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: carShareGreen,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
