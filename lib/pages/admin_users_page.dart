import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/resume_refresh.dart';
import '../theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';

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
    // A block body: an arrow that assigns the Future hands it back to setState, which throws.
    setState(() {
      _users = _loadUsers();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
  }

  List<Map<String, dynamic>> _filterUsers(List<Map<String, dynamic>> users) {
    final query = _search.text.trim().toLowerCase();
    return users
        .where((user) {
          final matchesSearch =
              query.isEmpty ||
              [
                user['fullName'],
                user['email'],
                user['phone'],
              ].any((value) => '$value'.toLowerCase().contains(query));
          final matchesRole =
              _roleFilter == 'all' || user['role'] == _roleFilter;
          final matchesStatus =
              _statusFilter == 'all' ||
              user['status'] == _statusFilter.toUpperCase();
          return matchesSearch && matchesRole && matchesStatus;
        })
        .toList(growable: false);
  }

  Future<void> _showDetails(Map<String, dynamic> user) async {
    final name = user['fullName'] as String? ?? 'User account';
    final status = user['status'] as String? ?? 'ACTIVE';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        title: Row(
          children: [
            InitialsAvatar(initials: _initial(name), size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusChip(
                        label: _label(status),
                        colour: _statusColour(status),
                      ),
                      AdminPill(_label(user['role']), colour: carShareMuted),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminFact('Email', '${user['email'] ?? '—'}'),
            AdminFact('Phone', '${user['phone'] ?? '—'}'),
            AdminFact('Created', _date(user['createdAt'])),
            if (user['statusUntil'] != null)
              AdminFact('Status ends', _date(user['statusUntil'])),
            if ((user['statusReason'] as String? ?? '').isNotEmpty)
              AdminFact('Status reason', '${user['statusReason']}'),
            AdminFact(
              'Profile photo',
              user['hasProfilePhoto'] == true ? 'Added' : 'Not added',
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _editUser(user);
            },
            child: const Text('Edit account'),
          ),
          FilledButton(
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Name is required.'
                      : null,
                  onSaved: (value) => fullName = value!.trim(),
                ),
                TextFormField(
                  initialValue: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (value) =>
                      value == null ||
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
                  validator: (value) =>
                      value == null ||
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
                    DropdownMenuItem(value: 'WARNING', child: Text('Warning')),
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
                    decoration: const InputDecoration(labelText: 'Duration'),
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

    final needsExpiry =
        result['status'] == 'WARNING' || result['status'] == 'SUSPENDED';
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ResumeRefresh(onResume: _refresh, child: _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      title: const Text('CarShare Admin'),
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load the accounts',
                    line: snapshot.error.toString(),
                  ),
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
                  const SizedBox(height: 12),
                  _FilterRow(
                    label: 'Role',
                    selected: _roleFilter,
                    options: const [
                      ('all', 'All'),
                      ('passenger', 'Passengers'),
                      ('driver', 'Drivers'),
                      ('admin', 'Admins'),
                    ],
                    onSelected: (value) => setState(() => _roleFilter = value),
                  ),
                  const SizedBox(height: 8),
                  _FilterRow(
                    label: 'Status',
                    selected: _statusFilter,
                    options: const [
                      ('all', 'All'),
                      ('ACTIVE', 'Active'),
                      ('WARNING', 'Warning'),
                      ('SUSPENDED', 'Suspended'),
                      ('BANNED', 'Banned'),
                    ],
                    onSelected: (value) =>
                        setState(() => _statusFilter = value),
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
                          const SizedBox(height: 40),
                          EmptyState(
                            icon: Icons.people_outline,
                            title: (snapshot.data ?? const []).isEmpty
                                ? 'No user accounts yet'
                                : 'No users match',
                            line: (snapshot.data ?? const []).isEmpty
                                ? 'Accounts appear here once people sign up.'
                                : 'Try another search or clear the filters.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: users.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _userCard(users[index]),
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
    return AdminCard(
      onTap: _working ? null : () => _showDetails(user),
      child: Row(
        children: [
          InitialsAvatar(initials: _initial(name), size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: carShareText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user['email'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: carShareMuted, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user['phone'] ?? ''} · ${_label(user['role'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: carShareMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: _label(status), colour: _statusColour(status)),
        ],
      ),
    );
  }

  Color _statusColour(String status) => status == 'ACTIVE'
      ? carShareGreen
      : (status == 'BANNED' ? carShareDanger : carShareWarning);

  String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

  String _label(Object? value) {
    final text = '$value'.toLowerCase();
    if (text.isEmpty || text == 'null') return 'Unknown';
    return text[0].toUpperCase() + text.substring(1);
  }

  String _date(Object? value) => adminDate(value, fallback: '—');
}

/// A labelled row of choice chips: the filter of a list (one option selected at a time).
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String selected;
  final List<(String, String)> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 52,
        child: Text(
          label,
          style: const TextStyle(
            color: carShareMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (value, text) = options[index];
              final on = value == selected;
              return ChoiceChip(
                label: Text(text),
                selected: on,
                showCheckmark: false,
                onSelected: (_) => onSelected(value),
                backgroundColor: Colors.white,
                selectedColor: carShareGreen,
                side: BorderSide(color: on ? carShareGreen : carShareBorder),
                shape: const StadiumBorder(),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : carShareMuted,
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
