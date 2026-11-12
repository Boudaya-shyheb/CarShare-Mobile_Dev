import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/primary_button.dart';
import 'sign_in_page.dart';
import 'sign_up_page.dart';

/// The mockup's welcome screen: a full-width green "map" with the route and the logo on top,
/// and a white sheet with rounded top corners holding the title and the two buttons. The map is
/// a static gradient and a painted route, not a live map.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  /// Height the white sheet needs for its text and buttons; the green part takes the rest.
  static const _sheetHeight = 392.0;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    // White status-bar icons over the green part.
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final heroHeight = (constraints.maxHeight - _sheetHeight).clamp(
            240.0,
            560.0,
          );
          return SingleChildScrollView(
            child: Column(
              children: [
                _Hero(height: heroHeight),
                const _Sheet(),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height + MediaQuery.paddingOf(context).top,
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF34D399), carShareGreen, carShareGreenDark],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_outlined,
                    color: carShareGreen,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'CarShare',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 36,
          bottom: 72,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: carShareSuccess),
                  SizedBox(width: 8),
                  Text(
                    'Your next ride starts here',
                    style: TextStyle(
                      color: carShareText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) => Transform.translate(
    // The sheet overlaps the bottom of the green part, which is what gives it rounded corners.
    offset: const Offset(0, -32),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Share the ride,\nsplit the road.',
            style: TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Find drivers going your way in real time, book a seat in '
            'seconds and follow your trip live.',
            style: TextStyle(color: carShareMuted, height: 1.5, fontSize: 15),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Get started',
            onPressed: () => Navigator.pushNamed(context, SignUpPage.routeName),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.pushNamed(context, SignInPage.routeName),
              child: const Text(
                'I already have an account',
                style: TextStyle(color: carShareText),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The dotted route with its two end points and the car badge half-way, drawn over the gradient.
class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * .17, size.height * .76);
    final end = Offset(size.width * .83, size.height * .33);
    final middle = Offset(size.width * .48, size.height * .56);

    final dot = Paint()..color = Colors.white;
    const steps = 18;
    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      final point = Offset.lerp(start, end, t)!;
      if ((point - middle).distance < 44) continue; // leave room for the car badge
      canvas.drawCircle(point, 3, dot);
    }
    for (final point in [start, end]) {
      canvas.drawCircle(point, 12, dot);
      canvas.drawCircle(point, 7, Paint()..color = carShareSuccess);
    }
    canvas.drawCircle(middle, 24, dot);
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.directions_car_outlined.codePoint),
        style: TextStyle(
          fontFamily: Icons.directions_car_outlined.fontFamily,
          package: Icons.directions_car_outlined.fontPackage,
          fontSize: 26,
          color: carShareGreen,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, middle - Offset(icon.width / 2, icon.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
