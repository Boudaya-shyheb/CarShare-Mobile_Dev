import 'package:flutter/material.dart';

import '../models/vehicle.dart';
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
      if (mounted)
        _showMessage(
          '${vehicle.brand} ${vehicle.model} is now your default vehicle.',
        );
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
    appBar: AppBar(title: const Text('My Vehicles')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : _addVehicle,
      icon: const Icon(Icons.add),
      label: const Text('Add Vehicle'),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _vehicles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _vehicleCard(_vehicles[index]),
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
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openDetails(vehicle),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: vehicle.photos.isEmpty
                  ? const SizedBox(
                      width: 92,
                      height: 92,
                      child: ColoredBox(
                        color: Color(0xFFF1F5F4),
                        child: Icon(
                          Icons.directions_car_outlined,
                          size: 34,
                          color: Color(0xFF718096),
                        ),
                      ),
                    )
                  : VehiclePhotoImage(
                      url: vehicle.photos.first.url,
                      width: 92,
                      height: 92,
                      borderRadius: BorderRadius.circular(12),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${vehicle.brand} ${vehicle.model}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (vehicle.isDefault)
                        const Icon(
                          Icons.star_rounded,
                          color: carShareGreen,
                          size: 20,
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Vehicle actions',
                        onSelected: (action) {
                          switch (action) {
                            case 'view':
                              _openDetails(vehicle);
                            case 'edit':
                              _editVehicle(vehicle);
                            case 'default':
                              _setDefault(vehicle);
                            case 'delete':
                              _deleteVehicle(vehicle);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('View details'),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit vehicle'),
                          ),
                          if (!vehicle.isDefault)
                            const PopupMenuItem(
                              value: 'default',
                              child: Text('Set as default'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete vehicle'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    '${vehicle.year} · ${vehicle.color} · ${vehicle.registrationNumber}',
                    style: const TextStyle(color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vehicle.seatsNumber} seats · ${_titleCase(vehicle.trunkSize)} trunk · ${vehicle.airConditioning ? 'Air conditioning' : 'No air conditioning'}',
                    style: const TextStyle(color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _statusLabel(vehicle.status),
                      if (vehicle.isDefault)
                        const Chip(
                          label: Text('Default'),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            color: carShareGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _statusLabel(String status) => Chip(
    label: Text(_titleCase(status)),
    visualDensity: VisualDensity.compact,
    backgroundColor: status == 'ACTIVE'
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFFFE4E6),
  );

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();
}
