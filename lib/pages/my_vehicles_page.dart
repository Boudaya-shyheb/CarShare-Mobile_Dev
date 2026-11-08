import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../models/vehicle_registration.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
    appBar: AppBar(
      title: const Text('My vehicles'),
      actions: [
        IconButton(
          tooltip: 'Add a vehicle',
          onPressed: _loading ? null : _addVehicle,
          icon: const Icon(Icons.add_circle, color: Color(0xFF00A884)),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _vehicles.length + 2,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
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
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44, color: carShareGreen),
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 18),
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
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.directions_car_outlined,
            size: 56,
            color: carShareGreen,
          ),
          const SizedBox(height: 16),
          Text(
            'No vehicles yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a vehicle to get ready to publish a trip.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF718096)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _addVehicle,
            icon: const Icon(Icons.add),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    ),
  );

  Widget _vehicleCard(Vehicle vehicle) => Card(
    margin: EdgeInsets.zero,
    elevation: 2,
    shadowColor: const Color(0x1A23344D),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openDetails(vehicle),
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 112,
                child: vehicle.photos.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFD8F9EA),
                        child: Icon(
                          Icons.directions_car_outlined,
                          size: 50,
                          color: Color(0xFF00A884),
                        ),
                      )
                    : VehiclePhotoImage(
                        url: vehicle.photos.first.url,
                        width: double.infinity,
                        height: 112,
                      ),
              ),
              if (vehicle.isDefault)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Default',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: _statusLabel(vehicle.status),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${vehicle.brand} ${vehicle.model}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit vehicle',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editVehicle(vehicle),
                    icon: const Icon(Icons.edit, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Delete vehicle',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteVehicle(vehicle),
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      backgroundColor: const Color(0xFFFFE7E7),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ],
              ),
              Text(
                '${vehicle.color} · ${vehicle.year} · ${_displayPlate(vehicle.registrationNumber)}',
                style: const TextStyle(color: Color(0xFF718096), fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _infoChip(Icons.people_alt, '${vehicle.seatsNumber} seats'),
                  _infoChip(
                    Icons.luggage_outlined,
                    'Trunk: ${_titleCase(vehicle.trunkSize)}',
                  ),
                  _infoChip(
                    Icons.ac_unit,
                    vehicle.airConditioning ? 'A/C' : 'No A/C',
                  ),
                ],
              ),
              if (!vehicle.isDefault)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _setDefault(vehicle),
                    icon: const Icon(Icons.star_outline, size: 17),
                    label: const Text('Set as default'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _statusLabel(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: status == 'ACTIVE'
          ? const Color(0xFFD1FAE5)
          : status == 'REPORTED'
          ? const Color(0xFFFFE4E6)
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _titleCase(status),
      style: TextStyle(
        color: status == 'ACTIVE'
            ? const Color(0xFF047857)
            : status == 'REPORTED'
            ? const Color(0xFFBE123C)
            : const Color(0xFF64748B),
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    ),
  );

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F5F9),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF344054)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _addVehicleTile() => OutlinedButton.icon(
    onPressed: _addVehicle,
    icon: const Icon(Icons.add, color: Color(0xFF00A884)),
    label: const Text('Add another vehicle'),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF00A884),
      backgroundColor: const Color(0xFFF8FFFB),
      side: const BorderSide(color: Color(0xFF00A884)),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  Widget _defaultVehicleTip() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0FDF8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, color: Color(0xFF00A884), size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your default vehicle can be pre-selected when publishing a trip.',
            style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
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
