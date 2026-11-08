import 'package:carshare/models/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses vehicle and photo references from the API', () {
    final vehicle = Vehicle.fromJson({
      'id': 'vehicle-1',
      'brand': 'Toyota',
      'model': 'Yaris',
      'year': 2022,
      'color': 'White',
      'registrationNumber': '123 TU 4567',
      'seatsNumber': 5,
      'trunkSize': 'MEDIUM',
      'airConditioning': true,
      'status': 'ACTIVE',
      'defaultVehicle': true,
      'photos': [
        {
          'id': 'photo-1',
          'url': '/vehicles/vehicle-1/photos/photo-1',
          'mimeType': 'image/jpeg',
        },
      ],
    });

    expect(vehicle.id, 'vehicle-1');
    expect(vehicle.isDefault, isTrue);
    expect(vehicle.photos.single.url, '/vehicles/vehicle-1/photos/photo-1');
  });

  test('serializes only fields accepted by vehicle create and update', () {
    const vehicle = Vehicle(
      id: '',
      brand: 'Toyota',
      model: 'Yaris',
      year: 2022,
      color: 'White',
      registrationNumber: '123 TU 4567',
      seatsNumber: 5,
      trunkSize: 'MEDIUM',
      airConditioning: true,
      status: 'ACTIVE',
      isDefault: false,
      photos: [],
    );

    expect(vehicle.toJson(), {
      'brand': 'Toyota',
      'model': 'Yaris',
      'year': 2022,
      'color': 'White',
      'registrationNumber': '123 TU 4567',
      'seatsNumber': 5,
      'trunkSize': 'MEDIUM',
      'airConditioning': true,
    });
  });
}
