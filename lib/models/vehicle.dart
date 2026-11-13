class VehiclePhoto {
  const VehiclePhoto({
    required this.id,
    required this.url,
    required this.mimeType,
    this.isPrimary = false,
  });

  final String id;
  final String url;
  final String mimeType;
  final bool isPrimary;

  factory VehiclePhoto.fromJson(Map<String, dynamic> json) => VehiclePhoto(
    id: json['id'] as String,
    url: json['url'] as String,
    mimeType: json['mimeType'] as String,
    isPrimary: json['primary'] as bool? ?? false,
  );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.registrationNumber,
    required this.seatsNumber,
    required this.trunkSize,
    required this.airConditioning,
    required this.status,
    required this.isDefault,
    required this.photos,
    this.insuranceExpiryDate,
    this.inspectionExpiryDate,
    this.reviewStatus = 'PENDING',
    this.reviewReason,
    this.tripsCompleted = 0,
  });

  final String id;
  final String brand;
  final String model;
  final int year;
  final String color;
  final String registrationNumber;
  final int seatsNumber;
  final String trunkSize;
  final bool airConditioning;
  final String status;
  final bool isDefault;
  final List<VehiclePhoto> photos;
  final DateTime? insuranceExpiryDate;
  final DateTime? inspectionExpiryDate;

  /// PENDING until CarShare support has looked at it, then APPROVED or REJECTED.
  final String reviewStatus;
  final String? reviewReason;

  /// How many trips this vehicle has finished: "Used in N trips".
  final int tripsCompleted;

  bool get isApproved => reviewStatus == 'APPROVED';

  /// A vehicle can drive a trip only when support approved it and it is not reported or inactive.
  bool get canDriveTrips => isApproved && status == 'ACTIVE';

  VehiclePhoto? get primaryPhoto {
    for (final photo in photos) {
      if (photo.isPrimary) return photo;
    }
    return photos.isEmpty ? null : photos.first;
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as String,
    brand: json['brand'] as String,
    model: json['model'] as String,
    year: json['year'] as int,
    color: json['color'] as String,
    registrationNumber: json['registrationNumber'] as String,
    seatsNumber: json['seatsNumber'] as int,
    trunkSize: json['trunkSize'] as String,
    airConditioning: json['airConditioning'] as bool,
    status: json['status'] as String,
    isDefault: json['defaultVehicle'] as bool,
    photos: (json['photos'] as List<dynamic>? ?? const [])
        .map((photo) => VehiclePhoto.fromJson(photo as Map<String, dynamic>))
        .toList(growable: false),
    insuranceExpiryDate: _dateFromJson(json['insuranceExpiryDate']),
    inspectionExpiryDate: _dateFromJson(json['inspectionExpiryDate']),
    reviewStatus: json['reviewStatus'] as String? ?? 'PENDING',
    reviewReason: json['reviewReason'] as String?,
    tripsCompleted: (json['tripsCompleted'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'brand': brand,
    'model': model,
    'year': year,
    'color': color,
    'registrationNumber': registrationNumber,
    'seatsNumber': seatsNumber,
    'trunkSize': trunkSize,
    'airConditioning': airConditioning,
    'insuranceExpiryDate': _dateToJson(insuranceExpiryDate),
    'inspectionExpiryDate': _dateToJson(inspectionExpiryDate),
  };

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'brand': brand,
    'model': model,
    'year': year,
    'color': color,
    'registrationNumber': registrationNumber,
    'seatsNumber': seatsNumber,
    'trunkSize': trunkSize,
    'airConditioning': airConditioning,
    'status': status,
    'defaultVehicle': isDefault,
    'photos': photos
        .map(
          (photo) => {
            'id': photo.id,
            'url': photo.url,
            'mimeType': photo.mimeType,
            'primary': photo.isPrimary,
          },
        )
        .toList(growable: false),
    'insuranceExpiryDate': _dateToJson(insuranceExpiryDate),
    'inspectionExpiryDate': _dateToJson(inspectionExpiryDate),
    'reviewStatus': reviewStatus,
    'reviewReason': reviewReason,
    'tripsCompleted': tripsCompleted,
  };

  static DateTime? _dateFromJson(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static String? _dateToJson(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-'
            '${value.month.toString().padLeft(2, '0')}-'
            '${value.day.toString().padLeft(2, '0')}';
}

String? vehicleDocumentReminder(DateTime? expiry, {DateTime? today}) {
  if (expiry == null) return null;
  final current = today ?? DateTime.now();
  final currentDate = DateTime(current.year, current.month, current.day);
  final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
  final daysRemaining = expiryDate.difference(currentDate).inDays;
  if (daysRemaining < 0) return 'Expired';
  if (daysRemaining == 0) return 'Expires today';
  if (daysRemaining <= 30) return 'Expires in $daysRemaining days';
  return null;
}
