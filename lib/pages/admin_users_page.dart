import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  late Future<List<Map<String, dynamic>>> _users = ApiClient.instance.getList(
    '/admin/users',
  );

  void _refresh() => setState(() {
    _users = ApiClient.instance.getList('/admin/users');
  });

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('User accounts'),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: _signOut,
          tooltip: 'Sign Out',
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        final users = snapshot.data ?? const <Map<String, dynamic>>[];
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: users.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    const Center(child: Text('No user accounts yet.')),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final status = (user['status'] as String? ?? 'ACTIVE')
                        .toLowerCase();
                    final name = user['fullName'] as String? ?? 'Unknown';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFD1FAE5),
                          child: Text(
                            name.isEmpty
                                ? '?'
                                : name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: carShareGreen),
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(
                          '${user['email']}\n${user['phone']} · ${(user['role'] as String? ?? '').toUpperCase()}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: TextStyle(
                            color: status == 'active'
                                ? carShareGreen
                                : Colors.deepOrange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}
