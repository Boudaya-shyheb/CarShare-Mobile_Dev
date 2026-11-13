import '../widgets/resume_refresh.dart';
import 'package:flutter/material.dart';

import '../widgets/admin_stats_bar.dart';
import 'admin_operations_page.dart';
import 'admin_users_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _selected = 0;

  /// Bumped when the app returns to the foreground, so the counters reload with the lists.
  int _resumes = 0;

  @override
  Widget build(BuildContext context) => ResumeRefresh(
    onResume: () => setState(() => _resumes++),
    child: _buildScaffold(),
  );

  Widget _buildScaffold() => Scaffold(
    body: Column(
      children: [
        // The counters sit above whichever tab is showing and reload when the tab changes.
        SafeArea(bottom: false, child: AdminStatsBar(reloadKey: _selected + _resumes * 10)),
        Expanded(
          // The strip already clears the status bar, so the tabs' own app bars must not pad again.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: IndexedStack(
              index: _selected,
              children: const [
                AdminUsersPage(),
                AdminOperationsPage(section: AdminSection.vehicles),
                AdminOperationsPage(section: AdminSection.trips),
                AdminOperationsPage(section: AdminSection.support),
                AdminOperationsPage(section: AdminSection.sanctions),
              ],
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
        NavigationDestination(icon: Icon(Icons.directions_car_outlined), selectedIcon: Icon(Icons.directions_car), label: 'Vehicles'),
        NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Trips'),
        NavigationDestination(icon: Icon(Icons.support_agent_outlined), selectedIcon: Icon(Icons.support_agent), label: 'Support'),
        NavigationDestination(icon: Icon(Icons.gavel_outlined), selectedIcon: Icon(Icons.gavel), label: 'Sanctions'),
      ],
    ),
  );
}
