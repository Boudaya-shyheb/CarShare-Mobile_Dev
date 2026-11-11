import 'package:flutter/material.dart';

import '../theme.dart';

/// An icon in a mint circle, a bold title and a muted line: the empty state the Reservation
/// screens draw, shared so the User screens can look the same.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
  });

  final IconData icon;
  final String title;
  final String line;

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
        ],
      ),
    ),
  );
}
