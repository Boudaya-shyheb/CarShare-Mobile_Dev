import 'package:carshare/models/trip_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the car on a trip, with the plate when the API sends it', () {
    final vehicle = TripVehicle.fromJson({
      'id': 'v1',
      'brand': 'Peugeot',
      'model': '208',
      'year': 2022,
      'color': 'Black',
      'registrationNumber': '123 TU 4567',
      'seatsNumber': 4,
      'airConditioning': true,
      'hasPhoto': true,
    });

    expect(vehicle.title, 'Peugeot 208');
    expect(vehicle.registrationNumber, '123 TU 4567');
    expect(vehicle.hasPhoto, isTrue);
  });

  test('a viewer who may not see the plate gets none', () {
    final vehicle = TripVehicle.fromJson({
      'id': 'v1',
      'brand': 'Peugeot',
      'model': '208',
      'year': 2022,
      'color': 'Black',
      'registrationNumber': null,
      'seatsNumber': 4,
      'airConditioning': false,
      'hasPhoto': false,
    });

    expect(vehicle.registrationNumber, isNull);
    expect(vehicle.hasPhoto, isFalse);
  });
}
