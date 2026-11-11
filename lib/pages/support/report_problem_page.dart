import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/support_evidence_section.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _evidenceController = SupportEvidenceController();
  String _category = 'Driver was late';
  int _tripIndex = 0;

  static const _trips = [
    _TripSample(
      route: 'Ennasr 2 → Lac 2',
      dateTime: 'Today · 08:15',
      participant: 'Driver: Ahmed B.',
    ),
    _TripSample(
      route: 'Lac 2 → Ennasr 2',
      dateTime: '2 Oct · 17:30',
      participant: 'Passenger: Mariem K.',
    ),
  ];

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
    _evidenceController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ticket submitted (demo only).')),
    );
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
                _TripCard(
                  trip: _trips[_tripIndex],
                  onChange: () => setState(
                    () => _tripIndex = (_tripIndex + 1) % _trips.length,
                  ),
                ),
                const SizedBox(height: 22),
                const _SectionTitle('What happened?'),
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
                const SizedBox(height: 18),
                SupportEvidenceSection(controller: _evidenceController),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: carShareTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.route_outlined, color: supportDarkGreen),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Trip data attached\nTimes, GPS route and trip events',
                          style: TextStyle(
                            fontSize: 12,
                            color: supportDarkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                PrimaryButton(label: 'Submit Ticket', onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onChange});

  final _TripSample trip;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: carShareBorder),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: carShareTint,
          child: Icon(Icons.directions_car_outlined, color: supportDarkGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.route,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${trip.dateTime}\n${trip.participant}',
                style: const TextStyle(fontSize: 11, color: carShareMuted),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    ),
  );
}

class _TripSample {
  const _TripSample({
    required this.route,
    required this.dateTime,
    required this.participant,
  });

  final String route;
  final String dateTime;
  final String participant;
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
