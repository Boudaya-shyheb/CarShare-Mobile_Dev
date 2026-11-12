import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/vehicle_catalog.dart';
import '../models/vehicle.dart';
import '../models/vehicle_registration.dart';
import '../services/api_client.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
import '../widgets/dashed_border.dart';
import '../widgets/primary_button.dart';
import '../widgets/round_back_button.dart';
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
  final _plateDigits = TextEditingController();
  final _seats = TextEditingController();
  final _picker = ImagePicker();
  final _vehicleService = VehicleService.instance;
  final _brandFocus = FocusNode();
  final _modelFocus = FocusNode();
  final List<XFile> _newPhotos = [];
  final List<VehiclePhoto> _existingPhotos = [];
  final Set<String> _removedPhotoIds = {};
  Vehicle? _savedVehicle;
  DateTime? _insuranceExpiryDate;
  DateTime? _inspectionExpiryDate;
  String? _selectedPrimaryPhotoId;
  XFile? _selectedNewPrimaryPhoto;
  VehiclePlateType _plateType = VehiclePlateType.tunisian;
  String _selectedColor = 'Grey';
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
      _seats.text = '4';
    } else {
      _brand.text = vehicle.brand;
      _model.text = vehicle.model;
      _year.text = vehicle.year.toString();
      _selectedColor = vehicle.color;
      final registration = vehicle.registrationNumber
          .replaceAll(RegExp(r'\s+'), '')
          .toUpperCase();
      if (registration.startsWith('RS')) {
        _plateType = VehiclePlateType.rs;
        _plateDigits.text = registration.substring(2);
      } else {
        _plateType = VehiclePlateType.tunisian;
        _plateDigits.text = registration.replaceAll(RegExp(r'\D'), '');
      }
      _seats.text = vehicle.seatsNumber.toString();
      _trunkSize = vehicle.trunkSize;
      _airConditioning = vehicle.airConditioning;
      _existingPhotos.addAll(vehicle.photos);
      _selectedPrimaryPhotoId = vehicle.primaryPhoto?.id;
      _insuranceExpiryDate = vehicle.insuranceExpiryDate;
      _inspectionExpiryDate = vehicle.inspectionExpiryDate;
      _savedVehicle = vehicle;
    }
    _plateDigits.addListener(_onPlateDigitsChanged);
  }

  void _onPlateDigitsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _plateDigits.dispose();
    _seats.dispose();
    _brandFocus.dispose();
    _modelFocus.dispose();
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
      if (mounted) {
        setState(() {
          _newPhotos.addAll(limited);
          final hasRemainingPhoto = _existingPhotos.any(
            (photo) => !_removedPhotoIds.contains(photo.id),
          );
          if (!hasRemainingPhoto &&
              _selectedPrimaryPhotoId == null &&
              _selectedNewPrimaryPhoto == null &&
              _newPhotos.isNotEmpty) {
            _selectedNewPrimaryPhoto = _newPhotos.first;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Photos could not be selected. Please try again.');
      }
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
    final digits = value?.trim() ?? '';
    if (digits.isEmpty) {
      return 'Registration number is required.';
    }
    return isValidVehiclePlateDigits(digits, _plateType)
        ? null
        : _plateType == VehiclePlateType.rs
        ? 'Enter the 6 digits after RS.'
        : 'Enter the 7 digits for the 123 TU 4567 format.';
  }

  String _platePreview() {
    final digits = _plateDigits.text;
    if (_plateType == VehiclePlateType.rs) {
      return 'RS ${digits.isEmpty ? '123456' : digits}';
    }
    if (digits.isEmpty) return '123 TU 4567';
    if (digits.length <= 3) return '$digits TU';
    return '${digits.substring(0, 3)} TU ${digits.substring(3)}';
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
    color: _selectedColor,
    registrationNumber: formatVehicleRegistration(
      _plateDigits.text.trim(),
      _plateType,
    ),
    seatsNumber: int.parse(_seats.text.trim()),
    trunkSize: _trunkSize,
    airConditioning: _airConditioning,
    status: _savedVehicle?.status ?? 'ACTIVE',
    isDefault: _savedVehicle?.isDefault ?? false,
    photos: _existingPhotos,
    insuranceExpiryDate: _insuranceExpiryDate,
    inspectionExpiryDate: _inspectionExpiryDate,
  );

  Future<void> _pickDocumentDate({required bool insurance}) async {
    final currentDate = insurance
        ? _insuranceExpiryDate
        : _inspectionExpiryDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selectedDate == null || !mounted) return;
    setState(() {
      if (insurance) {
        _insuranceExpiryDate = selectedDate;
      } else {
        _inspectionExpiryDate = selectedDate;
      }
    });
  }

  String _formatDate(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  void _removeExistingPhoto(VehiclePhoto photo) {
    setState(() {
      _removedPhotoIds.add(photo.id);
      if (_selectedPrimaryPhotoId == photo.id) {
        final remainingPhotos = _existingPhotos.where(
          (item) => item.id != photo.id && !_removedPhotoIds.contains(item.id),
        );
        if (remainingPhotos.isNotEmpty) {
          _selectedPrimaryPhotoId = remainingPhotos
              .firstWhere(
                (item) => item.isPrimary,
                orElse: () => remainingPhotos.first,
              )
              .id;
          _selectedNewPrimaryPhoto = null;
        } else {
          _selectedPrimaryPhotoId = null;
          _selectedNewPrimaryPhoto = _newPhotos.isEmpty
              ? null
              : _newPhotos.first;
        }
      }
    });
  }

  void _selectExistingPrimary(VehiclePhoto photo) {
    setState(() {
      _selectedPrimaryPhotoId = photo.id;
      _selectedNewPrimaryPhoto = null;
    });
  }

  void _selectNewPrimary(XFile image) {
    setState(() {
      _selectedPrimaryPhotoId = null;
      _selectedNewPrimaryPhoto = image;
    });
  }

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
                insuranceExpiryDate: draft.insuranceExpiryDate,
                inspectionExpiryDate: draft.inspectionExpiryDate,
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

      String? selectedNewPhotoId;
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
        final previousPhotoIds = _existingPhotos
            .map((photo) => photo.id)
            .toSet();
        final updated = await _vehicleService.uploadPhoto(
          vehicleId: vehicle.id,
          bytes: bytes,
          fileName: image.name,
          mimeType: mimeType,
        );
        if (identical(_selectedNewPrimaryPhoto, image)) {
          selectedNewPhotoId = updated.photos
              .firstWhere((photo) => !previousPhotoIds.contains(photo.id))
              .id;
        }
        _newPhotos.remove(image);
        _existingPhotos
          ..clear()
          ..addAll(updated.photos);
        _savedVehicle = updated;
        if (mounted) setState(() {});
      }

      final desiredPrimaryPhotoId =
          _selectedPrimaryPhotoId ?? selectedNewPhotoId;
      if (desiredPrimaryPhotoId != null &&
          _savedVehicle?.primaryPhoto?.id != desiredPrimaryPhotoId) {
        final updated = await _vehicleService.setPrimaryPhoto(
          vehicleId: vehicle.id,
          photoId: desiredPrimaryPhotoId,
        );
        _savedVehicle = updated;
        _existingPhotos
          ..clear()
          ..addAll(updated.photos);
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
    appBar: roundBackAppBar(
      context,
      title: _isEditing ? 'Edit vehicle' : 'Add a vehicle',
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                _photoSection(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _catalogField(brand: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _catalogField(brand: false)),
                  ],
                ),
                const SizedBox(height: 18),
                _sectionTitle('Year'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '2021'),
                  validator: _validateYear,
                ),
                const SizedBox(height: 18),
                _sectionTitle('Plate number'),
                const SizedBox(height: 8),
                SegmentedButton<VehiclePlateType>(
                  segments: const [
                    ButtonSegment(
                      value: VehiclePlateType.tunisian,
                      label: Text('123 TU 4567'),
                    ),
                    ButtonSegment(
                      value: VehiclePlateType.rs,
                      label: Text('RS 123456'),
                    ),
                  ],
                  selected: {_plateType},
                  showSelectedIcon: false,
                  onSelectionChanged: _saving
                      ? null
                      : (value) {
                          _plateType = value.first;
                          _plateDigits.clear();
                          setState(() {});
                        },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _plateDigits,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      _plateType == VehiclePlateType.rs ? 6 : 7,
                    ),
                  ],
                  decoration: InputDecoration(
                    hintText: _plateType == VehiclePlateType.rs
                        ? '123456'
                        : '1234567',
                    prefixText: _plateType == VehiclePlateType.rs ? 'RS ' : '',
                    counterText: '',
                  ),
                  validator: _validateRegistration,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 4),
                  child: Text(
                    'Preview: ${_platePreview()}',
                    style: const TextStyle(fontSize: 12, color: carShareMuted),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionTitle('Color'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final color in vehicleColors) _colorSwatch(color),
                    if (!vehicleColors.any(
                      (color) => color.name == _selectedColor,
                    ))
                      _colorSwatch(
                        VehicleColorOption(_selectedColor, 0xFF9CA3AF),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Seats offered'),
                          const SizedBox(height: 3),
                          const Text(
                            'Not counting the driver',
                            style: TextStyle(
                              color: carShareMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _seatCounter(),
                  ],
                ),
                const SizedBox(height: 18),
                _sectionTitle('Trunk size'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'SMALL', label: Text('Small')),
                    ButtonSegment(value: 'MEDIUM', label: Text('Medium')),
                    ButtonSegment(value: 'LARGE', label: Text('Large')),
                  ],
                  selected: {_trunkSize},
                  showSelectedIcon: false,
                  onSelectionChanged: _saving
                      ? null
                      : (value) => setState(() => _trunkSize = value.first),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.ac_unit, color: carShareGreen),
                  title: const Text(
                    'Air conditioning',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: carShareText,
                    ),
                  ),
                  value: _airConditioning,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _airConditioning = value),
                ),
                const SizedBox(height: 14),
                _documentsSection(),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: 'Save vehicle',
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

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: carShareText,
    ),
  );

  Widget _documentsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Vehicle documents'),
      const SizedBox(height: 4),
      const Text(
        'Dates only. Add reminders for upcoming expirations.',
        style: TextStyle(fontSize: 13, color: carShareMuted),
      ),
      const SizedBox(height: 10),
      _documentDateTile(
        label: 'Insurance expires',
        date: _insuranceExpiryDate,
        onChoose: () => _pickDocumentDate(insurance: true),
        onClear: () => setState(() => _insuranceExpiryDate = null),
      ),
      _documentDateTile(
        label: 'Technical inspection expires',
        date: _inspectionExpiryDate,
        onChoose: () => _pickDocumentDate(insurance: false),
        onClear: () => setState(() => _inspectionExpiryDate = null),
      ),
    ],
  );

  Widget _documentDateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onChoose,
    required VoidCallback onClear,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(date == null ? 'Not set' : _formatDate(date)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _saving ? null : onChoose,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          if (date != null)
            IconButton(
              tooltip: 'Clear date',
              onPressed: _saving ? null : onClear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    ),
  );

  Widget _catalogField({required bool brand}) {
    final controller = brand ? _brand : _model;
    final focusNode = brand ? _brandFocus : _modelFocus;
    final label = brand ? 'Brand' : 'Model';
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: (value) {
        final options = brand ? vehicleModelsByBrand.keys : _modelsForBrand();
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return options.take(8);
        return options
            .where((option) => option.toLowerCase().contains(query))
            .take(8);
      },
      onSelected: (value) {
        if (brand) {
          _brand.text = value;
          _model.clear();
        } else {
          _model.text = value;
        }
      },
      fieldViewBuilder: (context, textController, fieldFocus, onSubmitted) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(label),
              const SizedBox(height: 8),
              TextFormField(
                controller: textController,
                focusNode: fieldFocus,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: brand ? 'Peugeot' : '208',
                ),
                validator: (value) => _required(value, label),
                onFieldSubmitted: (_) => onSubmitted(),
              ),
            ],
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 5,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 280),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Iterable<String> _modelsForBrand() {
    final brand = vehicleModelsByBrand.keys.where(
      (key) => key.toLowerCase() == _brand.text.trim().toLowerCase(),
    );
    if (brand.isEmpty) return const [];
    return vehicleModelsByBrand[brand.first] ?? const [];
  }

  Widget _colorSwatch(VehicleColorOption option) {
    final selected = _selectedColor == option.name;
    return Tooltip(
      message: option.name,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${option.name} color',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _saving
              ? null
              : () => setState(() => _selectedColor = option.name),
          child: Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Color(option.value),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? carShareGreen : carShareBorder,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: option.name == 'White'
                        ? carShareGreen
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _seatCounter() {
    final count = int.tryParse(_seats.text) ?? 1;
    return FormField<int>(
      initialValue: count,
      validator: (_) => _validateSeats(_seats.text),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: carShareBackground,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white,
                    foregroundColor: carShareText,
                    minimumSize: const Size(40, 40),
                  ),
                  onPressed: _saving || count <= 1
                      ? null
                      : () => setState(() {
                          _seats.text = '${count - 1}';
                          field.didChange(count - 1);
                        }),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: carShareText,
                    ),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
                  onPressed: _saving || count >= 9
                      ? null
                      : () => setState(() {
                          _seats.text = '${count + 1}';
                          field.didChange(count + 1);
                        }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (field.hasError)
            Text(
              field.errorText!,
              style: const TextStyle(color: carShareDanger, fontSize: 12),
            ),
        ],
      ),
    );
  }

  /// Up to four photos, laid out as in the mockup: a wide dashed "Add photos" tile and square
  /// slots, with placeholders where no photo has been picked yet.
  Widget _photoSection() {
    final slots = <Widget>[
      for (final photo in _existingPhotos)
        if (!_removedPhotoIds.contains(photo.id)) _existingPhotoTile(photo),
      for (final image in _newPhotos) _newPhotoTile(image),
    ];
    final canAdd = slots.length < 4;
    while (canAdd && slots.length < 2) {
      slots.add(_emptySlot());
    }
    final children = <Widget>[
      if (canAdd) Expanded(flex: 2, child: _addPhotosTile()),
    ];
    for (final slot in slots) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 12));
      children.add(Expanded(child: slot));
    }
    return SizedBox(height: 104, child: Row(children: children));
  }

  Widget _emptySlot() => DecoratedBox(
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Center(
      child: Icon(Icons.directions_car_outlined, color: carShareMuted),
    ),
  );

  Widget _addPhotosTile() => InkWell(
    onTap: _saving ? null : _pickPhotos,
    borderRadius: BorderRadius.circular(18),
    child: const DashedBorder(
      radius: 18,
      fill: carShareTint,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 26, color: carShareGreen),
            SizedBox(height: 6),
            Text(
              'Add photos',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: carShareGreen,
              ),
            ),
            Text(
              'up to 4',
              style: TextStyle(fontSize: 12, color: carShareMuted),
            ),
          ],
        ),
      ),
    ),
  );

  /// The two small round buttons on a photo slot (make primary, remove).
  static final _slotButtonStyle = IconButton.styleFrom(
    minimumSize: const Size(26, 26),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _existingPhotoTile(VehiclePhoto photo) => Stack(
    fit: StackFit.expand,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: VehiclePhotoImage(
          url: photo.url,
          width: double.infinity,
          height: 104,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      Positioned(
        left: 4,
        bottom: 4,
        child: IconButton.filledTonal(
          style: _slotButtonStyle,
          tooltip: _selectedPrimaryPhotoId == photo.id
              ? 'Primary photo'
              : 'Set as primary photo',
          onPressed: _saving || _removedPhotoIds.contains(photo.id)
              ? null
              : () => _selectExistingPrimary(photo),
          icon: Icon(
            _selectedPrimaryPhotoId == photo.id
                ? Icons.star
                : Icons.star_outline,
            size: 15,
            color: _selectedPrimaryPhotoId == photo.id ? carShareGreen : null,
          ),
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: IconButton.filledTonal(
          style: _slotButtonStyle,
          tooltip: 'Remove photo',
          onPressed: _saving ? null : () => _removeExistingPhoto(photo),
          icon: const Icon(Icons.close, size: 15),
        ),
      ),
    ],
  );

  Widget _newPhotoTile(XFile image) => Stack(
    fit: StackFit.expand,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FutureBuilder<Uint8List>(
          future: image.readAsBytes(),
          builder: (context, snapshot) => snapshot.hasData
              ? Image.memory(snapshot.data!, fit: BoxFit.cover)
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
      Positioned(
        left: 4,
        bottom: 4,
        child: IconButton.filledTonal(
          style: _slotButtonStyle,
          tooltip: identical(_selectedNewPrimaryPhoto, image)
              ? 'Primary photo'
              : 'Set as primary photo',
          onPressed: _saving ? null : () => _selectNewPrimary(image),
          icon: Icon(
            identical(_selectedNewPrimaryPhoto, image)
                ? Icons.star
                : Icons.star_outline,
            size: 15,
            color: identical(_selectedNewPrimaryPhoto, image)
                ? carShareGreen
                : null,
          ),
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: IconButton.filledTonal(
          style: _slotButtonStyle,
          tooltip: 'Remove photo',
          onPressed: _saving
              ? null
              : () => setState(() {
                  _newPhotos.remove(image);
                  if (identical(_selectedNewPrimaryPhoto, image)) {
                    _selectedNewPrimaryPhoto = _newPhotos.isEmpty
                        ? null
                        : _newPhotos.first;
                  }
                }),
          icon: const Icon(Icons.close, size: 15),
        ),
      ),
    ],
  );
}

String vehicleErrorMessage(Object error) => error is ApiException
    ? error.message
    : 'We could not complete your request. Please try again.';
