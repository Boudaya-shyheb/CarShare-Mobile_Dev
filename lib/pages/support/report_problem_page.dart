import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/support_category.dart';
import '../../models/support_report_target.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/route_title.dart';
import '../../widgets/support_evidence_section.dart';
import '../../widgets/trip_formats.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  String _category = 'Driver was late';
  String? _categoryId;
  bool _saving = false;
  bool _restoringDraft = true;
  List<SupportCategory> _categories = const [];
  List<_TripOption> _tripOptions = const [];
  final List<SupportEvidence> _evidenceFiles = [];
  String? _selectedTripId;
  String? _selectedReservationId;
  String? _selectedTargetUserId;
  List<SupportReportTarget> _reportTargets = const [];
  bool _loadingTargets = false;

  @override
  void initState() {
    super.initState();
    _description.addListener(_saveDraft);
    _initialize();
  }

  Future<void> _initialize() async {
    await _restoreDraft();
    await Future.wait([_loadCategories(), _loadTrips()]);
    if (mounted) setState(() => _restoringDraft = false);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await SupportService.instance.categories();
      if (!mounted) return;
      SupportCategory? selected;
      for (final category in categories) {
        if (category.id == _categoryId || category.name == _category) {
          selected = category;
          break;
        }
      }
      selected ??= categories.isEmpty ? null : categories.first;
      final selectedCategory = selected;
      setState(() {
        _categories = categories;
        if (selectedCategory != null) {
          _categoryId = selectedCategory.id;
          _category = selectedCategory.name;
        }
      });
    } catch (_) {
      // A cached draft remains available while the API is offline.
    }
  }

  Future<void> _loadTrips() async {
    try {
      final options = <String, _TripOption>{};
      final trips = await ApiClient.instance.getList('/trips/mine');
      for (final trip in trips) {
        final id = trip['id'] as String?;
        if (id == null) continue;
        options[id] = _TripOption(id, null, _tripLabel(trip));
      }
      final reservations = await ApiClient.instance.getList(
        '/reservations/mine',
      );
      for (final reservation in reservations) {
        final trip = reservation['trip'];
        if (trip is! Map<String, dynamic>) continue;
        final id = trip['tripId'] as String?;
        final reservationId = reservation['id'] as String?;
        if (id == null) continue;
        options[id] = _TripOption(id, reservationId, _tripLabel(trip));
      }
      if (mounted) {
        setState(() => _tripOptions = options.values.toList(growable: false));
        if (_selectedTripId != null) {
          await _loadReportTargets(_selectedTripId!);
        }
      }
    } catch (_) {
      // A general support ticket can still be submitted without a trip reference.
    }
  }

  /// "Ennasr → Sousse · Today · 06:49": the first part of each place name and the departure,
  /// short enough for one line in the dropdown.
  String _tripLabel(Map<String, dynamic> trip) {
    final route =
        '${RouteTitle.shortName('${trip['originLabel']}')} → '
        '${RouteTitle.shortName('${trip['destinationLabel']}')}';
    final when = DateTime.tryParse('${trip['departureTime']}');
    return when == null ? route : '$route · ${formatWhen(when)}';
  }

  @override
  void dispose() {
    _description.removeListener(_saveDraft);
    _description.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final user = AuthService.instance.currentUser.value;
    if (user == null) return;
    final draft = await SupportService.instance.draft(user.id);
    if (draft == null || !mounted) return;
    _selectedTripId = draft['trip_id'] as String?;
    _selectedReservationId = draft['reservation_id'] as String?;
    _categoryId = draft['category_id'] as String?;
    _category = draft['category_name'] as String? ?? _category;
    _description.text = draft['description'] as String? ?? '';
  }

  void _saveDraft() {
    if (_restoringDraft) return;
    final user = AuthService.instance.currentUser.value;
    if (user == null) return;
    unawaited(
      SupportService.instance.saveDraft(
        userId: user.id,
        tripId: _selectedTripId,
        reservationId: _selectedReservationId,
        categoryId: _categoryId,
        categoryName: _category,
        title: _category,
        description: _description.text,
      ),
    );
  }

  String get _selectedTripLabel {
    for (final trip in _tripOptions) {
      if (trip.id == _selectedTripId) return trip.label;
    }
    return 'Selected trip';
  }

  Future<void> _addEvidence() async {
    if (_evidenceFiles.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to three photos.')),
      );
      return;
    }
    final photo = await pickSupportPhoto(context);
    if (photo != null && mounted) {
      setState(() => _evidenceFiles.add(photo));
    }
  }

  Future<void> _addDocument() async {
    if (_evidenceFiles.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to three files.')),
      );
      return;
    }
    final document = await pickSupportDocument(context);
    if (document != null && mounted) {
      setState(() => _evidenceFiles.add(document));
    }
  }

  Future<void> _selectTrip(String? tripId, String? reservationId) async {
    setState(() {
      _selectedTripId = tripId;
      _selectedReservationId = reservationId;
      _selectedTargetUserId = null;
      _reportTargets = const [];
    });
    _saveDraft();
    if (tripId != null) await _loadReportTargets(tripId);
  }

  Future<void> _loadReportTargets(String tripId) async {
    setState(() => _loadingTargets = true);
    try {
      final targets = await SupportService.instance.reportTargets(tripId);
      if (!mounted || _selectedTripId != tripId) return;
      SupportReportTarget? selected;
      for (final target in targets) {
        if (target.reservationId == _selectedReservationId) {
          selected = target;
          break;
        }
      }
      selected ??= targets.length == 1 ? targets.first : null;
      setState(() {
        _reportTargets = targets;
        _selectedTargetUserId = selected?.userId;
        if (selected != null) {
          _selectedReservationId = selected.reservationId;
        }
      });
      _saveDraft();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load trip participants: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Future<void> _uploadEvidence(String ticketId) async {
    for (final photo in _evidenceFiles) {
      final extension = photo.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };
      final bytes = photo.bytes;
      if (bytes == null) continue;
      await SupportService.instance.uploadEvidence(
        ticketId: ticketId,
        bytes: bytes,
        fileName: photo.name,
        mimeType: mimeType,
        type: extension == 'pdf' ? 'DOCUMENT' : 'PHOTO',
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTripId != null &&
        _reportTargets.isNotEmpty &&
        _selectedReservationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose the person concerned.')),
      );
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a support category.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ticket = await SupportService.instance.createTicket(
        tripId: _selectedTripId,
        reservationId: _selectedReservationId,
        categoryId: _categoryId!,
        category: _category,
        title: _category,
        description: _description.text.trim(),
      );
      final user = AuthService.instance.currentUser.value;
      if (user != null) await SupportService.instance.clearDraft(user.id);
      if (!mounted) return;
      try {
        await _uploadEvidence(ticket.id);
      } catch (error) {
        if (mounted) {
          Navigator.of(context).pop(
            'Ticket created, but a photo could not be uploaded: ${authErrorMessage(error)} You can retry from ticket details.',
          );
        }
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: carShareBackground,
      surfaceTintColor: carShareBackground,
      title: const Text(
        'Report a problem',
        style: TextStyle(fontWeight: FontWeight.w800, color: carShareText),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_selectedTripId != null) ...[
                  _AttachedTripCard(
                    label: _selectedTripLabel,
                    onChange: () => _selectTrip(null, null),
                  ),
                  if (_loadingTargets)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 18),
                      child: LinearProgressIndicator(),
                    )
                  else if (_reportTargets.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTargetUserId,
                      decoration: const InputDecoration(
                        labelText: 'Person concerned',
                        prefixIcon: Icon(Icons.person_search_outlined),
                      ),
                      items: _reportTargets
                          .map(
                            (target) => DropdownMenuItem(
                              value: target.userId,
                              child: Text(
                                '${target.fullName} · ${target.role.toLowerCase()}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      validator: (value) =>
                          value == null ? 'Choose the person concerned.' : null,
                      onChanged: (value) {
                        SupportReportTarget? selected;
                        for (final target in _reportTargets) {
                          if (target.userId == value) selected = target;
                        }
                        setState(() {
                          _selectedTargetUserId = value;
                          _selectedReservationId = selected?.reservationId;
                        });
                        _saveDraft();
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                ] else if (_tripOptions.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTripId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Related trip (optional)',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    selectedItemBuilder: (context) => [
                      for (final trip in _tripOptions)
                        Text(
                          trip.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    items: _tripOptions
                        .map(
                          (trip) => DropdownMenuItem(
                            value: trip.id,
                            child: Text(
                              trip.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      String? reservationId;
                      for (final option in _tripOptions) {
                        if (option.id == value) {
                          reservationId = option.reservationId;
                          break;
                        }
                      }
                      _selectTrip(value, reservationId);
                    },
                  ),
                  const SizedBox(height: 18),
                ],
                const _SectionTitle('What happened?'),
                const SizedBox(height: 10),
                ..._categories.map(
                  (category) => _CategoryOption(
                    label: category.name,
                    selected: category.id == _categoryId,
                    onTap: () {
                      setState(() {
                        _categoryId = category.id;
                        _category = category.name;
                      });
                      _saveDraft();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionTitle('Describe what happened'),
                const SizedBox(height: 8),
                CarShareTextField(
                  controller: _description,
                  label: 'Description',
                  icon: Icons.notes_rounded,
                  minLines: 4,
                  maxLines: 5,
                  hintText:
                      'Describe what happened and include any useful details.',
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please describe the problem.'
                      : null,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(child: _SectionTitle('Evidence')),
                    Text(
                      '${_evidenceFiles.length}/3',
                      style: const TextStyle(
                        color: carShareMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._evidenceFiles.asMap().entries.map(
                      (entry) => InputChip(
                        avatar: CircleAvatar(
                          backgroundImage: entry.value.bytes == null
                              ? null
                              : MemoryImage(entry.value.bytes!),
                          child: entry.value.bytes == null
                              ? const Icon(Icons.image_outlined, size: 16)
                              : null,
                        ),
                        label: SizedBox(
                          width: 130,
                          child: Text(
                            entry.value.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onDeleted: _saving
                            ? null
                            : () => setState(
                                () => _evidenceFiles.removeAt(entry.key),
                              ),
                      ),
                    ),
                    if (_evidenceFiles.length < 3)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addEvidence,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photo'),
                      ),
                    if (_evidenceFiles.length < 3)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addDocument,
                        icon: const Icon(Icons.attach_file_rounded),
                        label: const Text('Add PDF'),
                      ),
                  ],
                ),
                if (_selectedTripId != null) ...[
                  const SizedBox(height: 8),
                  const _TripDataChip(),
                ],
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Submit Ticket',
                  loading: _saving,
                  onPressed: _saving ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AttachedTripCard extends StatelessWidget {
  const _AttachedTripCard({required this.label, required this.onChange});

  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: carShareBorder),
    ),
    child: Row(
      children: [
        const Icon(Icons.route_rounded, color: supportGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    ),
  );
}

class _TripDataChip extends StatelessWidget {
  const _TripDataChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: carShareTint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route_outlined, size: 16, color: supportDarkGreen),
        SizedBox(width: 6),
        Text(
          'Trip data attached',
          style: TextStyle(
            color: supportDarkGreen,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _TripOption {
  const _TripOption(this.id, this.reservationId, this.label);
  final String id;
  final String? reservationId;
  final String label;
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? carShareTint : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? supportGreen : carShareBorder),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? supportGreen : carShareBorder,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: carShareText,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
  );
}
