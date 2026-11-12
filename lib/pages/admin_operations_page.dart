import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/admin_section_header.dart';

enum AdminSection { vehicles, trips, support, sanctions }

class AdminOperationsPage extends StatefulWidget {
  const AdminOperationsPage({super.key, required this.section});
  final AdminSection section;

  @override
  State<AdminOperationsPage> createState() => _AdminOperationsPageState();
}

class _AdminOperationsPageState extends State<AdminOperationsPage> {
  late Future<List<Map<String, dynamic>>> _items = _load();
  bool _showSecondary = false;
  bool _working = false;

  String get _path => switch (widget.section) {
    AdminSection.vehicles =>
      _showSecondary ? '/admin/driver-licenses' : '/admin/vehicles',
    AdminSection.trips =>
      _showSecondary ? '/admin/reservations' : '/admin/trips',
    AdminSection.support =>
      _showSecondary ? '/admin/lost-and-found' : '/admin/support-tickets',
    AdminSection.sanctions => '/admin/sanctions',
  };

  Future<List<Map<String, dynamic>>> _load() =>
      ApiClient.instance.getList(_path);

  void _refresh() {
    setState(() {
      _items = _load();
    });
  }

  Future<void> _signOut() => AuthService.instance.signOut();

  Future<void> _act(Future<void> Function() action, String message) async {
    setState(() => _working = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      AdminSection.vehicles => 'Driver & vehicle review',
      AdminSection.trips => 'Trips & reservations',
      AdminSection.support => 'Support & lost property',
      AdminSection.sanctions => 'Sanctions',
    };
    final subtitle = switch (widget.section) {
      AdminSection.vehicles =>
        _showSecondary
            ? 'Review driver licenses. Images are removed after a decision.'
            : 'Check vehicle details and document dates before approval.',
      AdminSection.trips =>
        'Review trip progress, reservations, and reported deviations.',
      AdminSection.support =>
        'Follow up support cases and close lost-and-found reports.',
      AdminSection.sanctions =>
        'Record a reasoned decision using the account rules.',
    };
    final icon = switch (widget.section) {
      AdminSection.vehicles => Icons.directions_car_filled_outlined,
      AdminSection.trips => Icons.route_outlined,
      AdminSection.support => Icons.support_agent_outlined,
      AdminSection.sanctions => Icons.gavel_outlined,
    };
    return Scaffold(
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
            onPressed: _working ? null : _signOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          adminSectionHeader(context, title, subtitle, icon),
          if (widget.section == AdminSection.vehicles ||
              widget.section == AdminSection.trips ||
              widget.section == AdminSection.support)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<bool>(
                segments: widget.section == AdminSection.vehicles
                    ? const [
                        ButtonSegment(value: false, label: Text('Vehicles')),
                        ButtonSegment(
                          value: true,
                          label: Text('Driver licenses'),
                        ),
                      ]
                    : widget.section == AdminSection.trips
                    ? const [
                        ButtonSegment(value: false, label: Text('Trips')),
                        ButtonSegment(value: true, label: Text('Reservations')),
                      ]
                    : const [
                        ButtonSegment(
                          value: false,
                          label: Text('Support tickets'),
                        ),
                        ButtonSegment(value: true, label: Text('Lost & found')),
                      ],
                selected: {_showSecondary},
                onSelectionChanged: (value) => setState(() {
                  _showSecondary = value.first;
                  _items = _load();
                }),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) return _EmptyView(message: _emptyMessage());
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _buildCard(items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.section == AdminSection.sanctions
          ? FloatingActionButton.extended(
              onPressed: _working ? null : _createSanction,
              icon: const Icon(Icons.add),
              label: const Text('Issue sanction'),
            )
          : null,
    );
  }

  String _emptyMessage() => switch (widget.section) {
    AdminSection.vehicles =>
      _showSecondary
          ? 'No driver licenses are waiting for review.'
          : 'No registered vehicles to review.',
    AdminSection.trips =>
      _showSecondary ? 'No reservations found.' : 'No trips found.',
    AdminSection.support =>
      _showSecondary ? 'No lost-and-found reports.' : 'No support tickets yet.',
    AdminSection.sanctions => 'No sanction decisions recorded.',
  };

  Widget _buildCard(Map<String, dynamic> item) => switch (widget.section) {
    AdminSection.vehicles =>
      _showSecondary ? _driverLicenseCard(item) : _vehicleCard(item),
    AdminSection.trips =>
      _showSecondary ? _reservationCard(item) : _tripCard(item),
    AdminSection.support =>
      _showSecondary ? _lostCard(item) : _ticketCard(item),
    AdminSection.sanctions => _sanctionCard(item),
  };

  Widget _vehicleCard(Map<String, dynamic> item) {
    final photos = (item['photos'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: carShareGreen),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${item['brand']} ${item['model']} · ${item['year']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                _status(item['reviewStatus']),
              ],
            ),
            const SizedBox(height: 8),
            Text('${item['ownerName']} · ${item['ownerEmail']}'),
            Text(
              'Plate ${item['registrationNumber']} · ${item['color']} · ${item['seats']} seats',
            ),
            Text('Insurance expires: ${_date(item['insuranceExpiryDate'])}'),
            Text('Inspection expires: ${_date(item['inspectionExpiryDate'])}'),
            if ((item['reviewReason'] as String? ?? '').isNotEmpty)
              Text('Review note: ${item['reviewReason']}'),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => _VehiclePhoto(
                    vehicleId: '${item['id']}',
                    photoId: '${photos[index]['id']}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () => _reviewVehicle(item, 'APPROVED'),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () => _reviewVehicle(item, 'REJECTED'),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverLicenseCard(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: carShareGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['fullName'] as String? ?? 'Driver',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              _status(item['status']),
            ],
          ),
          const SizedBox(height: 6),
          Text('${item['email']} · ${item['phone']}'),
          Text('License expires: ${_date(item['expiryDate'])}'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SizedBox(
                width: double.infinity,
                child: _DriverLicenseImage(userId: '${item['userId']}'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _reviewDriverLicense(item, 'APPROVED'),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _reviewDriverLicense(item, 'REJECTED'),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _reviewDriverLicense(
    Map<String, dynamic> item,
    String status,
  ) async {
    final reason = TextEditingController();
    var reasonMissing = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            status == 'APPROVED'
                ? 'Approve driver license'
                : 'Reject driver license',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: status == 'REJECTED'
                      ? 'Reason (required)'
                      : 'Review note (optional)',
                ),
              ),
              if (reasonMissing)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'A reason is required to reject this license.',
                    style: TextStyle(color: carShareDanger),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (status == 'REJECTED' && reason.text.trim().isEmpty) {
                  setDialogState(() => reasonMissing = true);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(status == 'APPROVED' ? 'Approve' : 'Reject'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      reason.dispose();
      return;
    }
    final note = reason.text.trim();
    reason.dispose();
    await _act(
      () async {
        await ApiClient.instance.put(
          '/admin/driver-licenses/${item['userId']}/review',
          {'status': status, 'reason': note},
        );
      },
      status == 'APPROVED'
          ? 'Driver license approved. The uploaded image was deleted.'
          : 'Driver license rejected. The uploaded image was deleted.',
    );
  }

  Widget _tripCard(Map<String, dynamic> item) => Card(
    child: ListTile(
      leading: Icon(
        item['incidentReported'] == true
            ? Icons.warning_amber_rounded
            : Icons.route,
        color: item['incidentReported'] == true
            ? Colors.deepOrange
            : carShareGreen,
      ),
      title: Text(
        '${item['origin']} → ${item['destination']}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item['driverName']} · ${_date(item['departureTime'])}\n${item['status']}${item['incidentReported'] == true ? ' · Reported deviation' : ''}${item['cancelReason'] == null ? '' : '\n${item['cancelReason']}'}',
      ),
      isThreeLine: true,
      trailing: _status(item['status']),
    ),
  );

  Widget _reservationCard(Map<String, dynamic> item) => Card(
    child: ListTile(
      leading: const Icon(Icons.event_seat_outlined, color: carShareGreen),
      title: Text(
        '${item['origin']} → ${item['destination']}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Passenger: ${item['passengerName']} · Driver: ${item['driverName']}\n${item['seats']} seat(s) · ${item['status']}${item['lateCancellation'] == true ? ' · Late cancellation' : ''}${item['cancelReason'] == null ? '' : '\n${item['cancelReason']}'}',
      ),
      isThreeLine: true,
      trailing: _status(item['status']),
    ),
  );

  Widget _ticketCard(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['title'] as String? ?? 'Support request',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _status(item['status']),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item['userName']} · ${item['userEmail']} · ${item['category']}',
          ),
          const SizedBox(height: 7),
          Text(item['description'] as String? ?? ''),
          if ((item['resolution'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Resolution: ${item['resolution']}'),
            ),
          if (item['status'] != 'RESOLVED')
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _updateTicket(item, 'UNDER_REVIEW'),
                  child: const Text('Start review'),
                ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _updateTicket(item, 'RESOLVED'),
                  child: const Text('Resolve'),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _lostCard(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['title'] as String? ?? 'Lost-and-found report',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _status(item['status']),
            ],
          ),
          const SizedBox(height: 6),
          Text('${item['type']} · Trip ${item['tripId']}'),
          Text(item['description'] as String? ?? ''),
          if (item['status'] == 'OPEN')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _working
                    ? null
                    : () => _act(() async {
                        await ApiClient.instance.put(
                          '/admin/lost-and-found/${item['id']}/resolve',
                          {},
                        );
                      }, 'Report marked resolved.'),
                icon: const Icon(Icons.done),
                label: const Text('Mark resolved'),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _sanctionCard(Map<String, dynamic> item) => Card(
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFEDD5),
        child: Icon(Icons.gavel, color: Colors.deepOrange),
      ),
      title: Text(
        '${item['userName']} · ${item['points']} point(s)',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${item['reason']}\nIssued ${_date(item['issuedAt'])} · Expires ${_date(item['expiresAt'])} · ${item['accountStatus']}',
      ),
      isThreeLine: true,
      trailing: _status(item['active'] == true ? 'ACTIVE' : 'EXPIRED'),
    ),
  );

  Future<void> _reviewVehicle(Map<String, dynamic> item, String status) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == 'APPROVED' ? 'Approve vehicle' : 'Reject vehicle',
        ),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: status == 'REJECTED'
                ? 'Reason (required)'
                : 'Review note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (status == 'REJECTED' && reason.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: Text(status == 'APPROVED' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _act(() async {
      await ApiClient.instance.put('/admin/vehicles/${item['id']}/review', {
        'status': status,
        'reason': reason.text.trim(),
      });
    }, 'Vehicle review saved.');
    reason.dispose();
  }

  Future<void> _updateTicket(Map<String, dynamic> item, String status) async {
    var resolution = '';
    if (status == 'RESOLVED') {
      final controller = TextEditingController();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resolve support request'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Resolution'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (accepted != true) {
        controller.dispose();
        return;
      }
      resolution = controller.text.trim();
      controller.dispose();
    }
    await _act(() async {
      await ApiClient.instance.put('/admin/support-tickets/${item['id']}', {
        'status': status,
        'resolution': resolution.isEmpty ? null : resolution,
      });
    }, 'Support case updated.');
  }

  Future<void> _createSanction() async {
    final people = await ApiClient.instance.getList('/admin/users');
    final targets = people.where((u) => u['role'] != 'admin').toList();
    if (!mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no eligible user accounts.')),
      );
      return;
    }
    final form = GlobalKey<FormState>();
    String? userId;
    var points = 1;
    var reason = '';
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Issue a sanction'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: userId,
                  decoration: const InputDecoration(labelText: 'User account'),
                  items: targets
                      .map(
                        (u) => DropdownMenuItem<String>(
                          value: u['id'] as String,
                          child: Text(
                            u['fullName'] as String? ??
                                u['email'] as String? ??
                                'User',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => userId = v),
                  validator: (v) => v == null ? 'Choose a user.' : null,
                ),
                DropdownButtonFormField<int>(
                  initialValue: points,
                  decoration: const InputDecoration(
                    labelText: 'Points · expire after 90 days',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 point')),
                    DropdownMenuItem(value: 3, child: Text('3 points')),
                    DropdownMenuItem(value: 6, child: Text('6 points')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => points = v);
                  },
                ),
                TextFormField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Decision reason',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'A reason is required.'
                      : null,
                  onSaved: (v) => reason = v!.trim(),
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
                if (!form.currentState!.validate()) return;
                form.currentState!.save();
                Navigator.pop(dialogContext, {
                  'userId': userId,
                  'points': points,
                  'reason': reason,
                });
              },
              child: const Text('Issue'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _act(() async {
      await ApiClient.instance.post(
        '/admin/users/${result['userId']}/sanctions',
        {'points': result['points'], 'reason': result['reason']},
      );
    }, 'Sanction recorded for 90 days.');
  }

  Widget _status(Object? value) {
    final text = '$value'.replaceAll('_', ' ').toLowerCase();
    final good = const {
      'approved',
      'active',
      'resolved',
      'completed',
    }.contains(text);
    final color = good
        ? carShareGreen
        : text.contains('reject') || text.contains('ban')
        ? carShareDanger
        : Colors.deepOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text.isEmpty ? 'Unknown' : text[0].toUpperCase() + text.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _date(Object? value) {
    if (value == null) return 'Not provided';
    final parsed = DateTime.tryParse('$value')?.toLocal();
    return parsed == null
        ? '$value'
        : '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _VehiclePhoto extends StatefulWidget {
  const _VehiclePhoto({required this.vehicleId, required this.photoId});
  final String vehicleId;
  final String photoId;
  @override
  State<_VehiclePhoto> createState() => _VehiclePhotoState();
}

class _VehiclePhotoState extends State<_VehiclePhoto> {
  late final Future<Uint8List> _bytes = ApiClient.instance.getBytes(
    '/admin/vehicles/${widget.vehicleId}/photos/${widget.photoId}',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const SizedBox(
          width: 72,
          height: 72,
          child: Icon(Icons.broken_image_outlined),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 72,
          height: 72,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          snapshot.data!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    },
  );
}

class _DriverLicenseImage extends StatefulWidget {
  const _DriverLicenseImage({required this.userId});
  final String userId;
  @override
  State<_DriverLicenseImage> createState() => _DriverLicenseImageState();
}

class _DriverLicenseImageState extends State<_DriverLicenseImage> {
  late final Future<Uint8List> _bytes = ApiClient.instance.getBytes(
    '/admin/driver-licenses/${widget.userId}/image',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const SizedBox(
          height: 150,
          child: Center(child: Text('License image unavailable.')),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 150,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return Image.memory(snapshot.data!, fit: BoxFit.contain);
    },
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 38, color: carShareMuted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 42, color: carShareGreen),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted),
          ),
        ],
      ),
    ),
  );
}
