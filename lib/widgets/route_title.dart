import 'package:flutter/material.dart';

import '../theme.dart';

/// "Origin → Destination" on one line. Both places always show: when they do not fit,
/// the shorter one keeps its natural width (up to half the line) and the longer one is
/// ellipsized into whatever is left, so a long origin never pushes the destination out.
class RouteTitle extends StatelessWidget {
  const RouteTitle({
    super.key,
    required this.origin,
    required this.destination,
    this.fontSize = 19,
  });

  final String origin;
  final String destination;
  final double fontSize;

  /// The first part of a Nominatim label: "Sousse" out of "Sousse, Délégation Sousse Medina".
  static String shortName(String label) {
    final first = label.split(',').first.trim();
    return first.isEmpty ? label : first;
  }

  static const _arrowWidth = 30.0; // 18 px icon + 6 px padding on each side

  TextStyle get _style => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: carShareText,
  );

  double _width(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        // Same inherited font as the Text widgets below, or the widths differ.
        style: DefaultTextStyle.of(context).style.merge(_style),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Minus the 1 px slack each place gets in _place, so the row can never overflow.
      final room = constraints.maxWidth - _arrowWidth - 2;
      final originWidth = _width(context, origin);
      final destinationWidth = _width(context, destination);
      var originMax = room / 2;
      var destinationMax = room / 2;
      if (originWidth + destinationWidth <= room) {
        originMax = originWidth;
        destinationMax = destinationWidth;
      } else if (destinationWidth < room / 2) {
        destinationMax = destinationWidth;
        originMax = room - destinationWidth;
      } else if (originWidth < room / 2) {
        originMax = originWidth;
        destinationMax = room - originWidth;
      }
      return Row(
        children: [
          _place(origin, originMax),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 18, color: carShareText),
          ),
          _place(destination, destinationMax),
        ],
      );
    },
  );

  // A hair of slack so rounding in the measurement never ellipsizes a text that fits.
  Widget _place(String text, double maxWidth) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth + 1),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _style,
    ),
  );
}
