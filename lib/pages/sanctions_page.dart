import 'package:flutter/material.dart';

import '../models/user_sanction.dart';
import '../services/auth_service.dart';
import '../services/user_management_service.dart';
import '../theme.dart';

class SanctionsPage extends StatefulWidget {
  const SanctionsPage({super.key});

  @override
  State<SanctionsPage> createState() => _SanctionsPageState();
}

class _SanctionsPageState extends State<SanctionsPage> {
  late final Future<List<UserSanction>> _sanctions = UserManagementService
      .instance
      .getSanctions();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sanction history')),
    body: FutureBuilder<List<UserSanction>>(
      future: _sanctions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error.toString(),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final entries = snapshot.data ?? const <UserSanction>[];
        final activePoints = entries
            .where((item) => item.active)
            .fold<int>(0, (sum, item) => sum + item.points);
        final status =
            AuthService.instance.currentUser.value?.status ?? 'ACTIVE';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.shield_outlined,
                  color: carShareGreen,
                ),
                title: Text('Account status: ${status.toLowerCase()}'),
                subtitle: Text('$activePoints active penalty points'),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You have no sanctions.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...entries.map(
                (item) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.active
                          ? const Color(0xFFFFE4E6)
                          : const Color(0xFFF1F5F9),
                      child: Text(
                        '${item.points}',
                        style: TextStyle(
                          color: item.active ? Colors.red : Colors.blueGrey,
                        ),
                      ),
                    ),
                    title: Text(item.reason),
                    subtitle: Text(
                      'Issued ${_date(item.issuedAt)} · Expires ${_date(item.expiresAt)}',
                    ),
                    trailing: Text(
                      item.active ? 'Active' : 'Expired',
                      style: TextStyle(
                        color: item.active ? Colors.red : Colors.blueGrey,
                      ),
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  String _date(DateTime value) =>
      value.toLocal().toIso8601String().substring(0, 10);
}
