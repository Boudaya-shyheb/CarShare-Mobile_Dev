import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// Presentation helpers shared by every reservation screen.
///
/// They live here rather than in one of the pages because the results list, the trip details
/// and both My trips tabs all have to render the same clock, price and status the same way.

/// "08:15", always in the device's own time zone — the API speaks UTC.
String formatClock(DateTime when) => DateFormat('HH:mm').format(when.toLocal());

/// "Today", "Tomorrow", "Yesterday", otherwise "Mon 9 Nov".
String formatDayLabel(DateTime when) {
  final local = when.toLocal();
  final days = DateUtils.dateOnly(local)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  return DateFormat('EEE d MMM').format(local);
}

/// "Today · 08:15".
String formatWhen(DateTime when) =>
    '${formatDayLabel(when)} · ${formatClock(when)}';

/// "8 DT" for a round price, "7.5 DT" otherwise. The API allows three decimals (millimes).
String formatPrice(double amount) {
  final text = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '$text DT';
}

/// "1 seat" / "3 seats".
String formatSeats(int seats) => seats == 1 ? '1 seat' : '$seats seats';

/// "350 m" below a kilometre, "1.1 km" above it.
String formatDistance(int metres) =>
    metres < 1000 ? '$metres m' : '${(metres / 100).round() / 10} km';

/// "45 min" / "1h 15". Returns a dash when the trip carries no duration.
String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0
      ? '${minutes ~/ 60}h'
      : '${minutes ~/ 60}h ${rest.toString().padLeft(2, '0')}';
}

/// Turns `DRIVER_EN_ROUTE` into "Driver en route".
String prettyStatus(String status) {
  final words = status.toLowerCase().replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// Colours for a reservation's status, as listed in the step 8 brief.
Color reservationStatusColour(String status) => switch (status) {
  'CONFIRMED' => carShareSuccess,
  'PENDING' => carShareWarning,
  'NO_SHOW' => carShareDanger,
  // REFUSED, CANCELLED and COMPLETED are all closed rows, and each sits in a tab of its own.
  _ => carShareMuted,
};

String reservationStatusLabel(String status) =>
    status == 'NO_SHOW' ? 'No-show' : prettyStatus(status);

/// Colours for a trip's status on the driver's cards.
Color tripStatusColour(String status) => switch (status) {
  'SCHEDULED' => carShareSuccess,
  'DRIVER_EN_ROUTE' ||
  'DRIVER_ARRIVED' ||
  'PICKED_UP' ||
  'IN_PROGRESS' => carShareWarning,
  _ => carShareMuted,
};

/// True once the driver is on the move, which is when a passenger may follow the trip.
bool tripIsTrackable(String tripStatus) => const {
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'PICKED_UP',
  'IN_PROGRESS',
}.contains(tripStatus);

/// "4.8" with one decimal, or "New driver" when nobody has rated them yet.
String formatRating(double? average, int count) {
  if (average == null || count <= 0) return 'New driver';
  final stars = average.toStringAsFixed(1);
  return '$stars · $count ${count == 1 ? 'rating' : 'ratings'}';
}

/// "AB" from "Ahmed Ben Salah", for the avatar circles.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}
