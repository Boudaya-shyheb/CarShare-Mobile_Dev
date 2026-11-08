import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
import '../widgets/vehicle_photo_image.dart';
import 'vehicle_form_page.dart';

class VehicleDetailsPage extends StatefulWidget {
  const VehicleDetailsPage({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  final _service = VehicleService.instance;
  late Vehicle _vehicle = widget.vehicle;
  bool _loading = false;
  int _currentPhoto = 0;

  Future<void> _refreshVehicle() async {
    setState(() => _loading = true);
    try {
      final updated = await _service.getVehicle(_vehicle.id);
      if (mounted) {
        setState(() {
          _vehicle = updated;
          _currentPhoto = 0;
        });
      }
    } catch (error) {
      if (mounted) _showMessage(vehicleErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editVehicle() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VehicleFormPage(vehicle: _vehicle),
      ),
    );
    if (saved == true && mounted) await _refreshVehicle();
  }

  Future<void> _deleteVehicle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text(
          'Delete ${_vehicle.brand} ${_vehicle.model}? This action cannot be undone.',
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
    setState(() => _loading = true);
    try {
      await _service.deleteVehicle(_vehicle.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showMessage(vehicleErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
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
      title: const Text('Vehicle Details'),
      actions: [
        IconButton(
          tooltip: 'Edit vehicle',
          onPressed: _loading ? null : _editVehicle,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete vehicle',
          onPressed: _loading ? null : _deleteVehicle,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SizedBox(
                      height: 260,
                      child: _vehicle.photos.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFFF1F5F4),
                              child: Icon(
                                Icons.directions_car_outlined,
                                size: 72,
                                color: Color(0xFF718096),
                              ),
                            )
                          : PageView.builder(
                              itemCount: _vehicle.photos.length,
                              onPageChanged: (index) =>
                                  setState(() => _currentPhoto = index),
                              itemBuilder: (context, index) =>
                                  VehiclePhotoImage(
                                    url: _vehicle.photos[index].url,
                                    width: double.infinity,
                                    height: 260,
                                  ),
                            ),
                    ),
                    if (_vehicle.photos.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _vehicle.photos.length,
                            (index) => Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index == _currentPhoto
                                    ? carShareGreen
                                    : const Color(0xFFDCE4E9),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_vehicle.brand} ${_vehicle.model}',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (_vehicle.isDefault)
                            const Chip(
                              avatar: Icon(
                                Icons.star_rounded,
                                color: carShareGreen,
                                size: 18,
                              ),
                              label: Text('Default'),
                            ),
                        ],
                      ),
                    ),
                    if (_vehicle.status == 'REPORTED')
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'This vehicle has been reported and cannot be used for a new trip.',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    _detail('Year', '${_vehicle.year}', Icons.calendar_today),
                    _detail('Color', _vehicle.color, Icons.palette_outlined),
                    _detail(
                      'Registration number',
                      _vehicle.registrationNumber,
                      Icons.pin_outlined,
                    ),
                    _detail(
                      'Seats',
                      '${_vehicle.seatsNumber}',
                      Icons.event_seat_outlined,
                    ),
                    _detail(
                      'Trunk size',
                      _titleCase(_vehicle.trunkSize),
                      Icons.luggage_outlined,
                    ),
                    _detail(
                      'Air conditioning',
                      _vehicle.airConditioning ? 'Available' : 'Not available',
                      Icons.ac_unit,
                    ),
                    _detail(
                      'Status',
                      _titleCase(_vehicle.status),
                      Icons.info_outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
  );

  Widget _detail(String label, String value, IconData icon) => ListTile(
    leading: Icon(icon, color: carShareGreen),
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();
}
