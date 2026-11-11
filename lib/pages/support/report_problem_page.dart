import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/primary_button.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  String _category = 'Driver was late';
  bool _saving = false;
  List<_TripOption> _tripOptions = const [];
  String? _selectedTripId;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    try {
      final options = <String, _TripOption>{};
      final trips = await ApiClient.instance.getList('/trips/mine');
      for (final trip in trips) {
        final id = trip['id'] as String?;
        if (id == null) continue;
        options[id] = _TripOption(id, '${trip['originLabel']} → ${trip['destinationLabel']}');
      }
      final reservations = await ApiClient.instance.getList('/reservations/mine');
      for (final reservation in reservations) {
        final trip = reservation['trip'];
        if (trip is! Map<String, dynamic>) continue;
        final id = trip['tripId'] as String?;
        if (id == null) continue;
        options[id] = _TripOption(id, '${trip['originLabel']} → ${trip['destinationLabel']}');
      }
      if (mounted) setState(() => _tripOptions = options.values.toList(growable: false));
    } catch (_) {
      // A general support ticket can still be submitted without a trip reference.
    }
  }

  static const _categories = [
    'Driver was late',
    "Driver didn't show up",
    'Wrong route taken',
    'Behaviour issue',
    'Vehicle condition',
    'Passenger was absent',
  ];

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/support/tickets', {
        if (_selectedTripId != null) 'tripId': _selectedTripId,
        'category': _category,
        'title': _category,
        'description': _description.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your support request was sent.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
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
                const _SectionTitle('What happened?'),
                if (_tripOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTripId,
                    decoration: const InputDecoration(labelText: 'Related trip (optional)'),
                    items: _tripOptions.map((trip) => DropdownMenuItem(value: trip.id, child: Text(trip.label, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (value) => setState(() => _selectedTripId = value),
                  ),
                ],
                const SizedBox(height: 8),
                ..._categories.map(
                  (category) => _CategoryOption(
                    label: category,
                    selected: category == _category,
                    onTap: () => setState(() => _category = category),
                  ),
                ),
                const SizedBox(height: 18),
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
                const SizedBox(height: 26),
                PrimaryButton(label: 'Submit Ticket', loading: _saving, onPressed: _saving ? null : _submit),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TripOption {
  const _TripOption(this.id, this.label);
  final String id;
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
