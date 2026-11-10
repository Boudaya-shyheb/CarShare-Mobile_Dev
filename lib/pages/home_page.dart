import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'profile_page.dart';
import 'my_vehicles_page.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.user});

  final UserProfile user;

  bool get _isDriver => user.role.toLowerCase() == 'driver';

  void _openVehicles(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyVehiclesPage()),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/sign-in', (_) => false);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'CarShare',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        if (_isDriver)
          IconButton(
            tooltip: 'My Vehicles',
            onPressed: () => _openVehicles(context),
            icon: const Icon(Icons.directions_car_outlined),
          ),
        IconButton(
          tooltip: 'Profile',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const ProfilePage())),
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: 'Sign Out',
          onPressed: () => _signOut(context),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.waving_hand_rounded,
                          color: carShareGreen,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome,',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: carShareGreen,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You’re all set for your next journey.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        margin: const EdgeInsets.only(bottom: 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          _isDriver ? 'Driver' : 'Passenger',
                          style: const TextStyle(
                            color: carShareGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_isDriver) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 20),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openVehicles(context),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.directions_car_outlined,
                                      color: carShareGreen,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'My Vehicles',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Add or manage your vehicles',
                                          style: TextStyle(
                                            color: Color(0xFF718096),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _openVehicles(context),
                            icon: const Icon(Icons.directions_car_filled),
                            label: const Text('Open Vehicle Management'),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _signOut(context),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
