import 'package:flutter/material.dart';

import '../theme.dart';

/// A small coloured pill: the status on a reservation or trip card, the match percentage on a
/// result card. The background is the label's own colour, softened.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.colour,
    this.bold = true,
  });

  final String label;
  final Color colour;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: colour,
      ),
    ),
  );
}

/// The tinted circle with a person's initials, used wherever a driver or passenger is named.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    this.size = 46,
    this.background = carShareTint,
    this.foreground = carShareGreen,
  });

  final String initials;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Text(
      initials,
      style: TextStyle(
        fontSize: size * 0.35,
        fontWeight: FontWeight.w800,
        color: foreground,
      ),
    ),
  );
}

/// The white rounded card every list row on the reservation screens sits in.
class CarShareCard extends StatelessWidget {
  const CarShareCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(carShareCardRadius),
      boxShadow: const [carShareCardShadow],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(carShareCardRadius),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
