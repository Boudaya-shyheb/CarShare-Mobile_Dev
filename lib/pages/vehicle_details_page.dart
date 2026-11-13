import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../models/vehicle_registration.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
import '../widgets/round_back_button.dart';
import '../widgets/status_chip.dart';
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
  late final PageController _photoController;

  @override
  void initState() {
    super.initState();
    _currentPhoto = _primaryPhotoIndex(_vehicle);
    _photoController = PageController(initialPage: _currentPhoto);
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  int _primaryPhotoIndex(Vehicle vehicle) {
    if (vehicle.photos.isEmpty) return 0;
    final index = vehicle.photos.indexWhere(
      (photo) => photo.id == vehicle.primaryPhoto?.id,
    );
    return index < 0 ? 0 : index;
  }

  Future<void> _refreshVehicle() async {
    setState(() => _loading = true);
    try {
      final updated = await _service.getVehicle(_vehicle.id);
      if (mounted) {
        setState(() {
          _vehicle = updated;
          _currentPhoto = _primaryPhotoIndex(updated);
        });
        if (_photoController.hasClients) {
          _photoController.jumpToPage(_currentPhoto);
        }
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
            child: const Text(
              'Delete',
              style: TextStyle(color: carShareDanger),
            ),
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
    backgroundColor: carShareBackground,
    appBar: roundBackAppBar(
      context,
      title: 'Vehicle details',
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
        const SizedBox(width: 12),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(carShareCardRadius),
                      child: SizedBox(
                        height: 230,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_vehicle.photos.isEmpty)
                              const ColoredBox(
                                color: carShareTint,
                                child: Icon(
                                  Icons.directions_car_outlined,
                                  size: 72,
                                  color: carShareGreen,
                                ),
                              )
                            else
                              PageView.builder(
                                controller: _photoController,
                                itemCount: _vehicle.photos.length,
                                onPageChanged: (index) =>
                                    setState(() => _currentPhoto = index),
                                itemBuilder: (context, index) =>
                                    VehiclePhotoImage(
                                      url: _vehicle.photos[index].url,
                                      width: double.infinity,
                                      height: 230,
                                    ),
                              ),
                            if (_vehicle.photos.isNotEmpty &&
                                _vehicle.photos[_currentPhoto].id ==
                                    _vehicle.primaryPhoto?.id)
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star_rounded,
                                        color: carShareGreen,
                                        size: 18,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Primary photo',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: carShareText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_vehicle.photos.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
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
                                    : carShareBorder,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_vehicle.brand} ${_vehicle.model}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: carShareText,
                            ),
                          ),
                        ),
                        if (_vehicle.isDefault)
                          const StatusChip(
                            label: 'Default',
                            colour: carShareGreen,
                          ),
                      ],
                    ),
                    if (_vehicle.status == 'REPORTED')
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'This vehicle has been reported and cannot be used for a new trip.',
                          style: TextStyle(color: carShareDanger),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _surface(
                      child: Column(
                        children: [
                          _detail('Year', '${_vehicle.year}', Icons.event),
                          _detail(
                            'Color',
                            _vehicle.color,
                            Icons.palette_outlined,
                          ),
                          _detail(
                            'Registration number',
                            displayVehicleRegistration(
                              _vehicle.registrationNumber,
                            ),
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
                            _vehicle.airConditioning
                                ? 'Available'
                                : 'Not available',
                            Icons.ac_unit,
                          ),
                          _detail(
                            'Status',
                            _titleCase(_vehicle.status),
                            Icons.info_outline,
                          ),
                          _detail(
                            'Review',
                            switch (_vehicle.reviewStatus) {
                              'APPROVED' => 'Approved',
                              'REJECTED' =>
                                'Rejected${(_vehicle.reviewReason ?? '').isEmpty ? '' : ': ${_vehicle.reviewReason}'}',
                              _ => 'Waiting for approval',
                            },
                            Icons.verified_outlined,
                          ),
                          _detail(
                            'Used in',
                            _vehicle.tripsCompleted == 1
                                ? '1 trip'
                                : '${_vehicle.tripsCompleted} trips',
                            Icons.route_outlined,
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _documentSection(),
                  ],
                ),
              ),
            ),
          ),
  );

  /// White rounded card with the app's soft shadow: the container of every block on the page.
  Widget _surface({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(carShareCardRadius),
      boxShadow: const [carShareCardShadow],
    ),
    child: child,
  );

  /// One row of the details card. Label and value share one size; the value is the bold one.
  Widget _detail(
    String label,
    String value,
    IconData icon, {
    bool last = false,
  }) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: carShareGreen, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: carShareMuted),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
            ),
          ],
        ),
      ),
      if (!last) const Divider(indent: 48),
    ],
  );

  Widget _documentSection() => _surface(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle documents',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 12),
          _documentRow('Insurance', _vehicle.insuranceExpiryDate),
          const Divider(height: 24),
          _documentRow('Technical inspection', _vehicle.inspectionExpiryDate),
        ],
      ),
    ),
  );

  Widget _documentRow(String label, DateTime? expiry) {
    if (expiry == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: carShareMuted),
            ),
          ),
          const Text(
            'Not set',
            style: TextStyle(fontSize: 15, color: carShareMuted),
          ),
        ],
      );
    }

    final reminder = vehicleDocumentReminder(expiry);
    final reminderColor = reminder == 'Expired'
        ? carShareDanger
        : carShareWarning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: carShareMuted),
              ),
            ),
            Text(
              MaterialLocalizations.of(context).formatMediumDate(expiry),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: carShareText,
              ),
            ),
          ],
        ),
        if (reminder != null) ...[
          const SizedBox(height: 4),
          Text(
            reminder,
            style: TextStyle(
              color: reminderColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  String _titleCase(String value) =>
      value[0] + value.substring(1).toLowerCase();
}
