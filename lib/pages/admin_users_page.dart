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
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _users = _loadUsers();
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  bool _working = false;

  Future<List<Map<String, dynamic>>> _loadUsers() =>
      ApiClient.instance.getList('/admin/users');

  void _refresh() {
    setState(() => _users = _loadUsers());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  List<Map<String, dynamic>> _filterUsers(
    List<Map<String, dynamic>> users,
  ) {
    final query = _search.text.trim().toLowerCase();
    return users.where((user) {
      final matchesSearch = query.isEmpty ||
          [user['fullName'], user['email'], user['phone']]
              .any((value) => '$value'.toLowerCase().contains(query));
      final matchesRole =
          _roleFilter == 'all' || user['role'] == _roleFilter;
      final matchesStatus = _statusFilter == 'all' ||
          user['status'] == _statusFilter.toUpperCase();
      return matchesSearch && matchesRole && matchesStatus;
    }).toList(growable: false);
  }

  Future<void> _showDetails(Map<String, dynamic> user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(user['fullName'] as String? ?? 'User account'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _detail('Email', user['email']),
            _detail('Phone', user['phone']),
            _detail('Role', _label(user['role'])),
            _detail('Status', _label(user['status'])),
            _detail('Created', _date(user['createdAt'])),
            if (user['statusUntil'] != null)
              _detail('Status ends', _date(user['statusUntil'])),
            if ((user['statusReason'] as String? ?? '').isNotEmpty)
              _detail('Status reason', user['statusReason']),
            _detail(
              'Profile photo',
              user['hasProfilePhoto'] == true ? 'Added' : 'Not added',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _editUser(user);
            },
            child: const Text('Edit account'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _changeStatus(user);
            },
            child: const Text('Change status'),
          ),
        ],
      ),
    );
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    var fullName = user['fullName'] as String? ?? '';
    var phone = user['phone'] as String? ?? '';
    var email = user['email'] as String? ?? '';
    var role = user['role'] as String? ?? 'passenger';

    final changes = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Edit user account'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                      ? 'Name is required.'
                      : null,
                  onSaved: (value) => fullName = value!.trim(),
                ),
                TextFormField(
                  initialValue: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (value) => value == null ||
                          !RegExp(r'^\+?[0-9][0-9\s().-]{5,19}$')
                              .hasMatch(value.trim())
                      ? 'Enter a valid phone number.'
                      : null,
                  onSaved: (value) => phone = value!.trim(),
                ),
                TextFormField(
                  initialValue: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value == null ||
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value.trim())
                      ? 'Enter a valid email address.'
                      : null,
                  onSaved: (value) => email = value!.trim(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                      value: 'passenger',
                      child: Text('Passenger'),
                    ),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => role = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                Navigator.pop(dialogContext, {
                  'fullName': fullName,
                  'phone': phone,
                  'email': email,
                  'role': role,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (changes == null) return;
    await _runAdminAction(() async {
      await ApiClient.instance.put('/admin/users/${user['id']}', changes);
    }, 'User account updated.');
  }

  Future<void> _changeStatus(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    var status = user['status'] as String? ?? 'ACTIVE';
    var durationDays = 7;
    var statusReason = '';
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Change account status'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'WARNING',
                      child: Text('Warning'),
                    ),
                    DropdownMenuItem(
                      value: 'SUSPENDED',
                      child: Text('Suspended'),
                    ),
                    DropdownMenuItem(value: 'BANNED', child: Text('Banned')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                ),
                if (status == 'WARNING' || status == 'SUSPENDED') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: durationDays,
                    decoration: const InputDecoration(
                      labelText: 'Duration',
                    ),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 90, child: Text('90 days')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => durationDays = value);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for this change',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'A reason is required.'
                      : null,
                  onSaved: (value) => statusReason = value!.trim(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                Navigator.pop(dialogContext, {
                  'status': status,
                  'durationDays': durationDays,
                  'reason': statusReason,
                });
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final needsExpiry = result['status'] == 'WARNING' ||
        result['status'] == 'SUSPENDED';
    final expiresAt = needsExpiry
        ? DateTime.now()
              .toUtc()
              .add(Duration(days: result['durationDays']! as int))
              .toIso8601String()
        : null;
    await _runAdminAction(() async {
      await ApiClient.instance.put('/admin/users/${user['id']}/status', {
        'status': result['status'],
        'statusUntil': expiresAt,
        'reason': result['reason'],
      });
    }, 'Account status updated.');
  }

  Future<void> _runAdminAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (!mounted) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Admin · User accounts'),
      actions: [
        IconButton(
          onPressed: _working ? null : _refresh,
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

        final users = _filterUsers(snapshot.data ?? const []);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search name, email, or phone',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _roleFilter,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All roles'),
                            ),
                            DropdownMenuItem(
                              value: 'passenger',
                              child: Text('Passenger'),
                            ),
                            DropdownMenuItem(
                              value: 'driver',
                              child: Text('Driver'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Admin'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _roleFilter = value ?? 'all',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All statuses'),
                            ),
                            DropdownMenuItem(
                              value: 'ACTIVE',
                              child: Text('Active'),
                            ),
                            DropdownMenuItem(
                              value: 'WARNING',
                              child: Text('Warning'),
                            ),
                            DropdownMenuItem(
                              value: 'SUSPENDED',
                              child: Text('Suspended'),
                            ),
                            DropdownMenuItem(
                              value: 'BANNED',
                              child: Text('Banned'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _statusFilter = value ?? 'all',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: users.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Text(
                              (snapshot.data ?? const []).isEmpty
                                  ? 'No user accounts yet.'
                                  : 'No users match these filters.',
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: users.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _userCard(users[index]),
                      ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _userCard(Map<String, dynamic> user) {
    final name = user['fullName'] as String? ?? 'Unknown';
    final status = user['status'] as String? ?? 'ACTIVE';
    return Card(
      child: ListTile(
        onTap: _working ? null : () => _showDetails(user),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFD1FAE5),
          child: Text(
            name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: carShareGreen),
          ),
        ),
        title: Text(name),
        subtitle: Text(
          '${user['email'] ?? ''}\n${user['phone'] ?? ''} · ${_label(user['role'])}',
        ),
        isThreeLine: true,
        trailing: Text(
          _label(status),
          style: TextStyle(
            color: status == 'ACTIVE' ? carShareGreen : Colors.deepOrange,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('$label: ${value ?? '—'}'),
  );

  String _label(Object? value) {
    final text = '$value'.toLowerCase();
    if (text.isEmpty || text == 'null') return 'Unknown';
    return text[0].toUpperCase() + text.substring(1);
  }

  String _date(Object? value) {
    if (value == null) return '—';
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '$value';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
