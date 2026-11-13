import 'package:flutter/material.dart';

import '../theme.dart';

/// The line above a list of notifications: a short summary on the left ("3 unread of 5") and
/// the All / Unread switch on the right. Both tabs of the notifications page use it, so they
/// look the same.
class NotificationFilterBar extends StatelessWidget {
  const NotificationFilterBar({
    super.key,
    required this.summary,
    required this.showUnreadOnly,
    required this.onChanged,
  });

  final String summary;
  final bool showUnreadOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          summary,
          style: const TextStyle(
            color: carShareText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          minimumSize: WidgetStatePropertyAll(Size(0, 40)),
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('All')),
          ButtonSegment(value: true, label: Text('Unread')),
        ],
        selected: {showUnreadOnly},
        onSelectionChanged: (values) => onChanged(values.first),
      ),
    ],
  );
}
