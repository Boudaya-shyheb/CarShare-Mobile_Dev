import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import 'status_chip.dart';

/// Building blocks the admin and Support screens share, so a list row, a date or an enum code
/// reads the same everywhere. Visual only: nothing here touches a service or a route.

/// "13 Nov 2026", or [fallback] when there is no date (or it cannot be read).
String adminDate(Object? value, {String fallback = 'Not provided'}) {
  if (value == null || '$value'.isEmpty) return fallback;
  final parsed = value is DateTime ? value : DateTime.tryParse('$value');
  if (parsed == null) return '$value';
  return DateFormat('d MMM yyyy').format(parsed.toLocal());
}

/// "13 Nov, 14:30", with the year only when it is not this one.
String adminDateTime(Object? value, {String fallback = 'Not provided'}) {
  if (value == null || '$value'.isEmpty) return fallback;
  final parsed = value is DateTime ? value : DateTime.tryParse('$value');
  if (parsed == null) return '$value';
  final local = parsed.toLocal();
  final sameYear = local.year == DateTime.now().year;
  return DateFormat(sameYear ? 'd MMM, HH:mm' : 'd MMM yyyy, HH:mm')
      .format(local);
}

/// `BEHAVIOUR_ISSUE` -> "Behaviour issue". Codes are for the server, not for people.
String humanize(Object? code, {String fallback = 'Unknown'}) {
  final text = '${code ?? ''}'.trim().replaceAll('_', ' ').toLowerCase();
  if (text.isEmpty) return fallback;
  return text[0].toUpperCase() + text.substring(1);
}

/// "Due in 2 days", "Due today" or "Overdue by 3 days", with the colour that goes with it.
({String label, Color colour}) slaState(Object? deadline, {DateTime? now}) {
  final parsed = deadline == null ? null : DateTime.tryParse('$deadline');
  if (parsed == null) return (label: 'No deadline', colour: carShareMuted);
  final days = parsed.toLocal().difference(now ?? DateTime.now()).inHours / 24;
  if (days < 0) {
    final late = (-days).ceil();
    return (
      label: 'Overdue by $late ${late == 1 ? 'day' : 'days'}',
      colour: carShareDanger,
    );
  }
  if (days < 1) return (label: 'Due today', colour: carShareWarning);
  final left = days.floor();
  return (
    label: 'Due in $left ${left == 1 ? 'day' : 'days'}',
    colour: days < 2 ? carShareWarning : carShareGreen,
  );
}

/// The label and colour of a support priority score.
({String label, Color colour}) priorityState(Object? score) {
  final value = score is num
      ? score.toDouble()
      : double.tryParse('$score') ?? 0;
  return switch (value) {
    >= 60 => (label: 'Urgent', colour: carShareDanger),
    >= 40 => (label: 'High', colour: const Color(0xFFEA580C)),
    >= 25 => (label: 'Medium', colour: carShareWarning),
    _ => (label: 'Normal', colour: carShareGreen),
  };
}

/// The white card with the soft shadow every admin list row sits in (the same card as the
/// reservation lists).
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      CarShareCard(onTap: onTap, padding: padding, child: child);
}

/// A tinted square with an icon: the leading mark of a card.
class AdminIconBadge extends StatelessWidget {
  const AdminIconBadge(
    this.icon, {
    super.key,
    this.colour = carShareGreen,
    this.size = 44,
  });

  final IconData icon;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: colour, size: size * 0.5),
  );
}

/// One line of secondary information: a small icon and a muted text.
class AdminInfoLine extends StatelessWidget {
  const AdminInfoLine(
    this.icon,
    this.text, {
    super.key,
    this.maxLines = 2,
    this.colour = carShareMuted,
  });

  final IconData icon;
  final String text;
  final int maxLines;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: colour),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colour, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// A coloured pill used for priority, SLA and similar short facts (smaller than [StatusChip]).
class AdminPill extends StatelessWidget {
  const AdminPill(this.label, {super.key, required this.colour, this.icon});

  final String label;
  final Color colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: colour,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// The decision buttons of a review card: the main action filled, the destructive one outlined
/// in red. Both keep the tap target at 48 dp.
class AdminDecisionBar extends StatelessWidget {
  const AdminDecisionBar({
    super.key,
    required this.onApprove,
    required this.onReject,
    this.approveLabel = 'Approve',
    this.rejectLabel = 'Reject',
  });

  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final String approveLabel;
  final String rejectLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onApprove,
          icon: const Icon(Icons.check_rounded, size: 20),
          label: Text(approveLabel),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: carShareDanger,
            side: const BorderSide(color: carShareDangerTint, width: 1.5),
            backgroundColor: Colors.white,
          ),
          onPressed: onReject,
          icon: const Icon(Icons.close_rounded, size: 20),
          label: Text(rejectLabel),
        ),
      ),
    ],
  );
}

/// A titled block of an admin page: heading above, content in a white card.
class AdminBlock extends StatelessWidget {
  const AdminBlock({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: carShareGreen),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
      AdminCard(child: SizedBox(width: double.infinity, child: child)),
    ],
  );
}

/// A label above a value, for the key facts of a detail page.
class AdminFact extends StatelessWidget {
  const AdminFact(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(color: carShareMuted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: carShareText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Long technical content behind a "Show details" toggle.
class AdminCollapsible extends StatelessWidget {
  const AdminCollapsible({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      iconColor: carShareGreen,
      collapsedIconColor: carShareMuted,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: carShareGreen,
          fontSize: 14,
        ),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
