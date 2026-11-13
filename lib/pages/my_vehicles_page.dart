import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../models/vehicle_registration.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
import '../widgets/dashed_border.dart';
import '../widgets/empty_state.dart';
import '../widgets/round_back_button.dart';
import '../widgets/status_chip.dart';
import '../widgets/vehicle_photo_image.dart';
import 'vehicle_details_page.dart';
import 'vehicle_form_page.dart';

class MyVehiclesPage extends StatefulWidget {
  const MyVehiclesPage({super.key});

  @override
  State<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends State<MyVehiclesPage> {
  final _service = VehicleService.instance;
  List<Vehicle> _vehicles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await _service.getVehicles();
      if (mounted) setState(() => _vehicles = vehicles);
    } catch (error) {
      if (mounted) setState(() => _error = vehicleErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addVehicle() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const VehicleFormPage()),
    );
    if (saved == true && mounted) _loadVehicles();
  }

  Future<void> _openDetails(Vehicle vehicle) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VehicleDetailsPage(vehicle: vehicle),
      ),
    );
    if (changed == true && mounted) _loadVehicles();
  }

  Future<void> _editVehicle(Vehicle vehicle) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VehicleFormPage(vehicle: vehicle),
      ),
    );
    if (saved == true && mounted) _loadVehicles();
  }

  Future<void> _setDefault(Vehicle vehicle) async {
    try {
      await _service.setDefault(vehicle.id);
      await _loadVehicles();
      if (mounted) {
        _showMessage(
          '${vehicle.brand} ${vehicle.model} is now your default vehicle.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(vehicleErrorMessage(error));
    }
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text(
          'Delete ${vehicle.brand} ${vehicle.model}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: carShareDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteVehicle(vehicle.id);
      await _loadVehicles();
      if (mounted) _showMessage('Vehicle deleted.');
    } catch (error) {
      if (mounted) _showMessage(vehicleErrorMessage(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: roundBackAppBar(
      context,
      title: 'My vehicles',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 24),
          child: IconButton.filled(
            tooltip: 'Add a vehicle',
            onPressed: _loading ? null : _addVehicle,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _vehicles.isEmpty
              ? _errorState()
              : _vehicles.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _loadVehicles,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: _vehicles.length + 2,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      if (index < _vehicles.length) {
                        return _vehicleCard(_vehicles[index]);
                      }
                      if (index == _vehicles.length) return _addVehicleTile();
                      return _defaultVehicleTip();
                    },
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _errorState() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your vehicles',
            line: _error!,
          ),
          OutlinedButton.icon(
            onPressed: _loadVehicles,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyState(
            icon: Icons.directions_car_outlined,
            title: 'No vehicles yet',
            line: 'Add a vehicle to get ready to publish a trip.',
          ),
          FilledButton.icon(
            onPressed: _addVehicle,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    ),
  );

  /// The default vehicle is the big card of the mockup; the others are compact rows. Both open
  /// the details page when tapped anywhere; the buttons inside keep their own taps.
  Widget _vehicleCard(Vehicle vehicle) =>
      vehicle.isDefault ? _largeCard(vehicle) : _compactCard(vehicle);

  /// White rounded surface with the app's soft shadow, tappable as a whole.
  Widget _surface({required VoidCallback onTap, required Widget child}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(carShareCardRadius),
          boxShadow: const [carShareCardShadow],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(carShareCardRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      );

  Widget _largeCard(Vehicle vehicle) => _surface(
    onTap: () => _openDetails(vehicle),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 130,
                  child: vehicle.photos.isEmpty
                      ? const ColoredBox(
                          color: carShareTint,
                          child: Icon(
                            Icons.directions_car_outlined,
                            size: 56,
                            color: carShareGreen,
                          ),
                        )
                      : VehiclePhotoImage(
                          url: vehicle.primaryPhoto!.url,
                          width: double.infinity,
                          height: 130,
                        ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: carShareGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (vehicle.status != 'ACTIVE')
                Positioned(
                  top: 12,
                  right: 12,
                  child: _statusChip(vehicle.status),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${vehicle.brand} ${vehicle.model}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${vehicle.color} · ${vehicle.year} · '
            '${_displayPlate(vehicle.registrationNumber)}',
            style: const TextStyle(color: carShareMuted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _specChips(vehicle),
          ..._documentWarnings(vehicle),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _circleButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit vehicle',
                onPressed: () => _editVehicle(vehicle),
              ),
              const SizedBox(width: 10),
              _circleButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete vehicle',
                danger: true,
                onPressed: () => _deleteVehicle(vehicle),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _compactCard(Vehicle vehicle) => _surface(
    onTap: () => _openDetails(vehicle),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: vehicle.photos.isEmpty
                      ? const ColoredBox(
                          color: carShareBackground,
                          child: Icon(
                            Icons.directions_car_outlined,
                            color: carShareMuted,
                          ),
                        )
                      : VehiclePhotoImage(
                          url: vehicle.primaryPhoto!.url,
                          width: 56,
                          height: 56,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle.brand} ${vehicle.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: carShareText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vehicle.color} · ${vehicle.seatsNumber} seats · '
                      '${_displayPlate(vehicle.registrationNumber)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: carShareMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (vehicle.status != 'ACTIVE') ...[
                const SizedBox(width: 8),
                _statusChip(vehicle.status),
              ],
            ],
          ),
          ..._documentWarnings(vehicle),
          const SizedBox(height: 12),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _setDefault(vehicle),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: carShareTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_outline_rounded,
                        size: 18,
                        color: carShareGreen,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Set as default',
                        style: TextStyle(
                          color: carShareGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              _circleButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit vehicle',
                onPressed: () => _editVehicle(vehicle),
              ),
              const SizedBox(width: 10),
              _circleButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete vehicle',
                danger: true,
                onPressed: () => _deleteVehicle(vehicle),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// The round grey edit button and the round red delete button of the mockup.
  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool danger = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      backgroundColor: danger ? carShareDangerTint : carShareBackground,
      foregroundColor: danger ? carShareDanger : carShareText,
    ),
    icon: Icon(icon, size: 20),
  );

  /// A vehicle that is not plainly active says so: reported, or whatever else the server sets.
  Widget _statusChip(String status) => StatusChip(
    label: _titleCase(status),
    colour: status == 'REPORTED' ? carShareDanger : carShareMuted,
  );

  Widget _specChips(Vehicle vehicle) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      // Only an approved vehicle can drive a trip, so the review state is always visible.
      StatusChip(
        label: switch (vehicle.reviewStatus) {
          'APPROVED' => 'Approved',
          'REJECTED' => 'Rejected',
          _ => 'Waiting for approval',
        },
        colour: switch (vehicle.reviewStatus) {
          'APPROVED' => carShareGreen,
          'REJECTED' => carShareDanger,
          _ => carShareWarning,
        },
      ),
      _infoChip(
        Icons.route_outlined,
        vehicle.tripsCompleted == 1
            ? 'Used in 1 trip'
            : 'Used in ${vehicle.tripsCompleted} trips',
      ),
      _infoChip(Icons.groups_outlined, '${vehicle.seatsNumber} seats'),
      _infoChip(
        Icons.luggage_outlined,
        'Trunk: ${_titleCase(vehicle.trunkSize)}',
      ),
      _infoChip(Icons.ac_unit, vehicle.airConditioning ? 'A/C' : 'No A/C'),
    ],
  );

  List<Widget> _documentWarnings(Vehicle vehicle) {
    final documents = [
      ('Insurance', vehicle.insuranceExpiryDate),
      ('Inspection', vehicle.inspectionExpiryDate),
    ];
    final chips = [
      for (final (label, expiry) in documents)
        if (vehicleDocumentReminder(expiry) case final reminder?)
          _documentReminderChip('$label: $reminder'),
    ];
    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: chips),
    ];
  }

  Widget _documentReminderChip(String reminder) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: carShareDangerTint,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.event_busy_outlined, size: 14, color: carShareDanger),
        const SizedBox(width: 4),
        Text(
          reminder,
          style: const TextStyle(
            fontSize: 12,
            color: carShareDanger,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: carShareText),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: carShareText,
          ),
        ),
      ],
    ),
  );

  /// The dashed green box under the list ("+ Add another vehicle").
  Widget _addVehicleTile() => InkWell(
    onTap: _addVehicle,
    borderRadius: BorderRadius.circular(carShareCardRadius),
    child: const DashedBorder(
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: carShareGreen),
              SizedBox(width: 10),
              Text(
                'Add another vehicle',
                style: TextStyle(
                  color: carShareGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _defaultVehicleTip() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, color: carShareGreen, size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'The default vehicle is pre-selected when you publish a trip.',
            style: TextStyle(fontSize: 14, color: carShareMuted, height: 1.35),
          ),
        ),
      ],
    ),
  );

  String _displayPlate(String value) {
    return displayVehicleRegistration(value);
  }

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();
}
