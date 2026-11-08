import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/vehicle.dart';
import '../services/api_client.dart';
import '../services/vehicle_service.dart';
import '../widgets/primary_button.dart';
import '../widgets/vehicle_photo_image.dart';

class VehicleFormPage extends StatefulWidget {
  const VehicleFormPage({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  State<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends State<VehicleFormPage> {
  static const _maxPhotoSize = 5 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _color = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _seats = TextEditingController();
  final _picker = ImagePicker();
  final _vehicleService = VehicleService.instance;
  final List<XFile> _newPhotos = [];
  final List<VehiclePhoto> _existingPhotos = [];
  final Set<String> _removedPhotoIds = {};
  Vehicle? _savedVehicle;
  String _trunkSize = 'MEDIUM';
  bool _airConditioning = false;
  bool _saving = false;

  bool get _isEditing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    if (vehicle == null) {
      _year.text = DateTime.now().year.toString();
    } else {
      _brand.text = vehicle.brand;
      _model.text = vehicle.model;
      _year.text = vehicle.year.toString();
      _color.text = vehicle.color;
      _registrationNumber.text = vehicle.registrationNumber;
      _seats.text = vehicle.seatsNumber.toString();
      _trunkSize = vehicle.trunkSize;
      _airConditioning = vehicle.airConditioning;
      _existingPhotos.addAll(vehicle.photos);
      _savedVehicle = vehicle;
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _color.dispose();
    _registrationNumber.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final available =
        4 -
        _existingPhotos.length +
        _removedPhotoIds.length -
        _newPhotos.length;
    if (available <= 0) {
      _showMessage('A vehicle can have up to four photos.');
      return;
    }

    try {
      final selected = await _picker.pickMultiImage(
        limit: available,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (!mounted || selected.isEmpty) return;
      final accepted = <XFile>[];
      for (final image in selected) {
        final size = await image.length();
        if (size > _maxPhotoSize) {
          _showMessage('${image.name} is larger than 5 MB and was not added.');
          continue;
        }
        if (_mimeType(image) == null) {
          _showMessage('${image.name} is not a supported image format.');
          continue;
        }
        accepted.add(image);
      }
      final limited = accepted.take(available).toList();
      if (accepted.length > available) {
        _showMessage('A vehicle can have up to four photos.');
      }
      if (mounted) setState(() => _newPhotos.addAll(limited));
    } catch (_) {
      if (mounted)
        _showMessage('Photos could not be selected. Please try again.');
    }
  }

  String? _mimeType(XFile image) {
    final extension = image.name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label is required.' : null;

  String? _validateYear(String? value) {
    final year = int.tryParse(value?.trim() ?? '');
    if (year == null) return 'Enter a valid manufacturing year.';
    if (year < 1900 || year > DateTime.now().year) {
      return 'Enter a year between 1900 and ${DateTime.now().year}.';
    }
    return null;
  }

  String? _validateRegistration(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Registration number is required.';
    }
    return RegExp(
          r'^\d{3}\s+TU\s+\d{4}$',
          caseSensitive: false,
        ).hasMatch(value.trim())
        ? null
        : 'Use the Tunisian format: 123 TU 4567.';
  }

  String? _validateSeats(String? value) {
    final count = int.tryParse(value?.trim() ?? '');
    if (count == null || count < 1 || count > 9) {
      return 'Enter a number of seats from 1 to 9.';
    }
    return null;
  }

  Vehicle _formVehicle() => Vehicle(
    id: _savedVehicle?.id ?? '',
    brand: _brand.text.trim(),
    model: _model.text.trim(),
    year: int.parse(_year.text.trim()),
    color: _color.text.trim(),
    registrationNumber: _registrationNumber.text.trim().toUpperCase(),
    seatsNumber: int.parse(_seats.text.trim()),
    trunkSize: _trunkSize,
    airConditioning: _airConditioning,
    status: _savedVehicle?.status ?? 'ACTIVE',
    isDefault: _savedVehicle?.isDefault ?? false,
    photos: _existingPhotos,
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final pendingPhotoCount =
        _existingPhotos.length - _removedPhotoIds.length + _newPhotos.length;
    if (pendingPhotoCount > 4) {
      _showMessage('A vehicle can have up to four photos.');
      return;
    }

    setState(() => _saving = true);
    var vehicleSaved = false;
    try {
      final draft = _formVehicle();
      final vehicle = _savedVehicle == null
          ? await _vehicleService.createVehicle(draft)
          : await _vehicleService.updateVehicle(
              Vehicle(
                id: _savedVehicle!.id,
                brand: draft.brand,
                model: draft.model,
                year: draft.year,
                color: draft.color,
                registrationNumber: draft.registrationNumber,
                seatsNumber: draft.seatsNumber,
                trunkSize: draft.trunkSize,
                airConditioning: draft.airConditioning,
                status: _savedVehicle!.status,
                isDefault: _savedVehicle!.isDefault,
                photos: _existingPhotos,
              ),
            );
      if (!mounted) return;
      setState(() => _savedVehicle = vehicle);
      vehicleSaved = true;

      for (final photoId in _removedPhotoIds.toList()) {
        await _vehicleService.deletePhoto(
          vehicleId: vehicle.id,
          photoId: photoId,
        );
        _removedPhotoIds.remove(photoId);
        _existingPhotos.removeWhere((photo) => photo.id == photoId);
        if (mounted) setState(() {});
      }

      for (final image in _newPhotos.toList()) {
        final bytes = await image.readAsBytes();
        if (bytes.length > _maxPhotoSize) {
          throw const ApiException(
            'Each vehicle photo must be 5 MB or smaller.',
          );
        }
        final mimeType = _mimeType(image);
        if (mimeType == null) {
          throw const ApiException('Choose a JPG, PNG, or WebP image.');
        }
        final updated = await _vehicleService.uploadPhoto(
          vehicleId: vehicle.id,
          bytes: bytes,
          fileName: image.name,
          mimeType: mimeType,
        );
        _newPhotos.remove(image);
        _existingPhotos
          ..clear()
          ..addAll(updated.photos);
        _savedVehicle = updated;
        if (mounted) setState(() {});
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        final message = vehicleSaved
            ? 'Vehicle saved, but photo changes could not be completed: ${vehicleErrorMessage(error)}'
            : vehicleErrorMessage(error);
        _showMessage(message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isEditing ? 'Edit Vehicle' : 'Add Vehicle')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  controller: _brand,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  validator: (value) => _required(value, 'Brand'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _model,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Model'),
                  validator: (value) => _required(value, 'Model'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Manufacturing year',
                    hintText: '2024',
                  ),
                  validator: _validateYear,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _color,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Color'),
                  validator: (value) => _required(value, 'Color'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _registrationNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Registration number',
                    hintText: '123 TU 4567',
                  ),
                  validator: _validateRegistration,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _seats,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of seats',
                  ),
                  validator: _validateSeats,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _trunkSize,
                  decoration: const InputDecoration(labelText: 'Trunk size'),
                  items: const [
                    DropdownMenuItem(value: 'SMALL', child: Text('Small')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
                    DropdownMenuItem(value: 'LARGE', child: Text('Large')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _trunkSize = value);
                        },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Air conditioning'),
                  value: _airConditioning,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _airConditioning = value),
                ),
                const SizedBox(height: 12),
                Text(
                  'Vehicle photos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add up to four JPG, PNG, or WebP photos. Each photo must be 5 MB or smaller.',
                  style: TextStyle(color: Color(0xFF718096)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final photo in _existingPhotos)
                      if (!_removedPhotoIds.contains(photo.id))
                        _existingPhotoTile(photo),
                    for (final image in _newPhotos) _newPhotoTile(image),
                    if (_existingPhotos.length -
                            _removedPhotoIds.length +
                            _newPhotos.length <
                        4)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickPhotos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photos'),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: _isEditing ? 'Save Changes' : 'Add Vehicle',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _existingPhotoTile(VehiclePhoto photo) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: VehiclePhotoImage(
          url: photo.url,
          width: 96,
          height: 96,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      Positioned(
        top: 2,
        right: 2,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove photo',
          onPressed: _saving
              ? null
              : () => setState(() => _removedPhotoIds.add(photo.id)),
          icon: const Icon(Icons.close, size: 18),
        ),
      ),
    ],
  );

  Widget _newPhotoTile(XFile image) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 96,
          height: 96,
          child: FutureBuilder<Uint8List>(
            future: image.readAsBytes(),
            builder: (context, snapshot) => snapshot.hasData
                ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      Positioned(
        top: 2,
        right: 2,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove photo',
          onPressed: _saving
              ? null
              : () => setState(() => _newPhotos.remove(image)),
          icon: const Icon(Icons.close, size: 18),
        ),
      ),
    ],
  );
}

String vehicleErrorMessage(Object error) => error is ApiException
    ? error.message
    : 'We could not complete your request. Please try again.';
