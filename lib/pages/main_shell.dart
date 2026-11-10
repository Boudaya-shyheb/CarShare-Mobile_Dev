import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme.dart';
import 'lost_and_found_page.dart';
import 'profile_page.dart';
import 'reservation/home_search_page.dart';

/// Navigation shell for signed-in users.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user});

  static const routeName = '/home';

  final UserProfile user;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        HomeSearchPage(user: widget.user),
        const _ComingSoon(
          icon: Icons.route_outlined,
          title: 'My trips',
          line: 'Your reservations and published trips will appear here.',
          step: 'Step 8',
        ),
        const _ComingSoon(
          icon: Icons.navigation_outlined,
          title: 'Live',
          line: 'Follow a trip on the map once one is under way.',
          step: 'Step 9',
        ),
        const ProfilePage(),
        LostAndFoundPage(
          key: ValueKey(widget.user.id),
          userId: widget.user.id,
        ),
      ],
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: carShareBorder)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: carShareTint,
          labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? carShareGreen
                  : carShareMuted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? carShareGreen
                  : carShareMuted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route_rounded),
              label: 'Trips',
            ),
            NavigationDestination(
              icon: Icon(Icons.navigation_outlined),
              selectedIcon: Icon(Icons.navigation_rounded),
              label: 'Live',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Lost & Found',
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.line,
    required this.step,
  });

  final IconData icon;
  final String title;
  final String line;
  final String step;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: carShareText,
        ),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: carShareTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: carShareGreen),
              ),
              const SizedBox(height: 18),
              Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: carShareMuted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: carShareTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$step — coming next',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: carShareGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}