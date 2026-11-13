/// The car on a trip, as `GET /trips/{id}/vehicle` returns it.
///
/// Anybody signed in gets the model, colour and photo; the plate is only filled for the driver
/// and for people holding a confirmed seat, so it is nullable here.
class TripVehicle {
  const TripVehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.seatsNumber,
    required this.airConditioning,
    required this.hasPhoto,
    this.registrationNumber,
  });

  final String id;
  final String brand;
  final String model;
  final int year;
  final String color;
  final int seatsNumber;
  final bool airConditioning;
  final bool hasPhoto;
  final String? registrationNumber;

  String get title => '$brand $model';

  factory TripVehicle.fromJson(Map<String, dynamic> json) => TripVehicle(
    id: json['id'] as String,
    brand: json['brand'] as String,
    model: json['model'] as String,
    year: json['year'] as int,
    color: json['color'] as String,
    seatsNumber: json['seatsNumber'] as int,
    airConditioning: json['airConditioning'] as bool? ?? false,
    hasPhoto: json['hasPhoto'] as bool? ?? false,
    registrationNumber: json['registrationNumber'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'brand': brand,
    'model': model,
    'year': year,
    'color': color,
    'seatsNumber': seatsNumber,
    'airConditioning': airConditioning,
    'hasPhoto': hasPhoto,
    'registrationNumber': registrationNumber,
  };
}
