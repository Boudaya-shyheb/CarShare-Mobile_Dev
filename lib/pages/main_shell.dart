import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'profile_page.dart';
import 'reservation/home_search_page.dart';
import 'reservation/live_page.dart';
import 'reservation/my_trips_page.dart';

/// Which shell tab is showing. A page pushed on top of the shell — the booking screen, say —
/// sets this to send the user to another tab as it pops, which it cannot do through the
/// Navigator because the tabs are not routes.
final ValueNotifier<int> carShareShellTab = ValueNotifier<int>(0);

/// Which trip the Live tab should open. "Track live" on a My trips card sets it before
/// switching tabs; null lets the tab pick whichever trip is under way.
final ValueNotifier<String?> carShareLiveTripId = ValueNotifier<String?>(null);

/// The four-tab shell every signed-in non-admin user lands on.
///
/// The Profile tab shows the user module's existing [ProfilePage] unchanged. Trips and Live are
/// placeholders until steps 8 and 9.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user});

  static const routeName = '/home';

  final UserProfile user;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    carShareShellTab.addListener(_followTabRequest);
  }

  @override
  void dispose() {
    carShareShellTab.removeListener(_followTabRequest);
    super.dispose();
  }

  void _followTabRequest() {
    if (mounted && carShareShellTab.value != _tab) {
      setState(() => _tab = carShareShellTab.value);
    }
  }

  void _showTab(int index) {
    carShareShellTab.value = index;
    setState(() => _tab = index);
  }

  /// Ends the session. No navigation is needed afterwards: the gate in app.dart listens to
  /// AuthService.currentUser and swaps this shell for the Welcome page on its own. Popping to
  /// the first route first makes sure a pushed sub-page (Preferences, say) does not stay up.
  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthService.instance.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // The home tab draws its own full-bleed map, so the body goes behind nothing.
    body: IndexedStack(
      index: _tab,
      children: [
        HomeSearchPage(user: widget.user),
        MyTripsPage(user: widget.user),
        LivePage(user: widget.user),
        // ProfilePage belongs to the user module and builds its own Scaffold and AppBar, so
        // the sign-out control is laid over that AppBar's action slot rather than edited in.
        Stack(
          children: [
            const ProfilePage(),
            Positioned(
              // Lines the button up with the AppBar's own action slot: the status bar, then
              // the toolbar. Align would not do, as it does not stretch inside this stack.
              top: MediaQuery.of(context).padding.top,
              right: 4,
              height: kToolbarHeight,
              child: Center(
                child: _signingOut
                    ? const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        color: carShareText,
                        tooltip: 'Sign out',
                        onPressed: _signOut,
                      ),
              ),
            ),
          ],
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
          onDestinationSelected: _showTab,
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
          ],
        ),
      ),
    ),
  );
}
