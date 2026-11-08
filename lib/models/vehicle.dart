class VehiclePhoto {
  const VehiclePhoto({
    required this.id,
    required this.url,
    required this.mimeType,
  });

  final String id;
  final String url;
  final String mimeType;

  factory VehiclePhoto.fromJson(Map<String, dynamic> json) => VehiclePhoto(
    id: json['id'] as String,
    url: json['url'] as String,
    mimeType: json['mimeType'] as String,
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
  };
}
