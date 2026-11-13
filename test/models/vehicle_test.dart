import 'package:carshare/models/vehicle.dart';
import 'package:carshare/models/vehicle_registration.dart';
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
      'insuranceExpiryDate': '2027-04-15',
      'inspectionExpiryDate': '2026-12-01',
      'reviewStatus': 'APPROVED',
      'reviewReason': null,
      'tripsCompleted': 3,
      'photos': [
        {
          'id': 'photo-1',
          'url': '/vehicles/vehicle-1/photos/photo-1',
          'mimeType': 'image/jpeg',
          'primary': true,
        },
      ],
    });

    expect(vehicle.id, 'vehicle-1');
    expect(vehicle.isDefault, isTrue);
    expect(vehicle.primaryPhoto?.id, 'photo-1');
    expect(vehicle.insuranceExpiryDate, DateTime(2027, 4, 15));
    expect(vehicle.inspectionExpiryDate, DateTime(2026, 12, 1));
    expect(vehicle.photos.single.url, '/vehicles/vehicle-1/photos/photo-1');
    expect(vehicle.reviewStatus, 'APPROVED');
    expect(vehicle.tripsCompleted, 3);
    expect(
      Vehicle.fromJson(vehicle.toCacheJson()).toCacheJson(),
      vehicle.toCacheJson(),
    );
  });

  test('reads the review state and the completed-trip count', () {
    Map<String, dynamic> json(String review, String status) => {
      'id': 'v',
      'brand': 'Peugeot',
      'model': '208',
      'year': 2022,
      'color': 'Black',
      'registrationNumber': '123 TU 4567',
      'seatsNumber': 4,
      'trunkSize': 'MEDIUM',
      'airConditioning': true,
      'status': status,
      'defaultVehicle': false,
      'reviewStatus': review,
      'reviewReason': review == 'REJECTED' ? 'plate unreadable' : null,
      'tripsCompleted': 7,
      'photos': <dynamic>[],
    };

    final approved = Vehicle.fromJson(json('APPROVED', 'ACTIVE'));
    final pending = Vehicle.fromJson(json('PENDING', 'ACTIVE'));
    final rejected = Vehicle.fromJson(json('REJECTED', 'ACTIVE'));
    final reported = Vehicle.fromJson(json('APPROVED', 'REPORTED'));

    expect(approved.tripsCompleted, 7);
    expect(approved.canDriveTrips, isTrue);
    expect(pending.canDriveTrips, isFalse);
    expect(rejected.canDriveTrips, isFalse);
    expect(rejected.reviewReason, 'plate unreadable');
    expect(reported.canDriveTrips, isFalse, reason: 'approved but reported');
  });

  test('an older response without the new fields reads as pending, zero trips', () {
    final vehicle = Vehicle.fromJson({
      'id': 'v',
      'brand': 'Toyota',
      'model': 'Yaris',
      'year': 2020,
      'color': 'White',
      'registrationNumber': '123 TU 4567',
      'seatsNumber': 4,
      'trunkSize': 'SMALL',
      'airConditioning': false,
      'status': 'ACTIVE',
      'defaultVehicle': false,
    });

    expect(vehicle.reviewStatus, 'PENDING');
    expect(vehicle.tripsCompleted, 0);
    expect(vehicle.canDriveTrips, isFalse);
  });

  test('serializes only fields accepted by vehicle create and update', () {
    final vehicle = Vehicle(
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
      insuranceExpiryDate: DateTime(2027, 4, 15),
      inspectionExpiryDate: DateTime(2026, 12, 1),
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
      'insuranceExpiryDate': '2027-04-15',
      'inspectionExpiryDate': '2026-12-01',
    });
  });

  test('formats the two supported plate types from digits only', () {
    expect(
      formatVehicleRegistration('1234567', VehiclePlateType.tunisian),
      '123TU4567',
    );
    expect(
      formatVehicleRegistration('123456', VehiclePlateType.rs),
      'RS123456',
    );
    expect(
      isValidVehiclePlateDigits('1234567', VehiclePlateType.tunisian),
      isTrue,
    );
    expect(
      isValidVehiclePlateDigits('12345A7', VehiclePlateType.tunisian),
      isFalse,
    );
    expect(displayVehicleRegistration('123TU4567'), '123 TU 4567');
    expect(displayVehicleRegistration('RS123456'), 'RS 123456');
  });

  test('reminds about upcoming and expired vehicle documents', () {
    final today = DateTime(2026, 11, 8);
    expect(
      vehicleDocumentReminder(DateTime(2026, 11, 8), today: today),
      'Expires today',
    );
    expect(
      vehicleDocumentReminder(DateTime(2026, 12, 8), today: today),
      'Expires in 30 days',
    );
    expect(
      vehicleDocumentReminder(DateTime(2026, 11, 7), today: today),
      'Expired',
    );
    expect(vehicleDocumentReminder(DateTime(2027, 1, 1), today: today), isNull);
  });
}
