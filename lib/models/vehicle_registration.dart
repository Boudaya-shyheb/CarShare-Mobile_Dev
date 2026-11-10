enum VehiclePlateType { tunisian, rs }

String formatVehicleRegistration(String digits, VehiclePlateType type) =>
    type == VehiclePlateType.rs
    ? 'RS$digits'
    : '${digits.substring(0, 3)}TU${digits.substring(3)}';

String displayVehicleRegistration(String registrationNumber) {
  final normalized = registrationNumber
      .replaceAll(RegExp(r'\s+'), '')
      .toUpperCase();
  if (normalized.startsWith('RS')) {
    return 'RS ${normalized.substring(2)}';
  }
  if (RegExp(r'^\d{3}TU\d{4}$').hasMatch(normalized)) {
    return '${normalized.substring(0, 3)} TU ${normalized.substring(5)}';
  }
  return registrationNumber;
}

bool isValidVehiclePlateDigits(String digits, VehiclePlateType type) =>
    RegExp(r'^\d+$').hasMatch(digits) &&
    digits.length == (type == VehiclePlateType.rs ? 6 : 7);
