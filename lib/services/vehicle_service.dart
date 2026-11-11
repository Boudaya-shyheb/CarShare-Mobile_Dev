import 'dart:typed_data';

import '../models/vehicle.dart';
import 'api_client.dart';

class VehicleService {
  VehicleService._();
  static final instance = VehicleService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<Vehicle>> getVehicles() async =>
      (await _api.getList('/vehicles'))
          .map(Vehicle.fromJson)
          .toList(growable: false);

  Future<Vehicle> getVehicle(String id) async =>
      Vehicle.fromJson(await _api.get('/vehicles/$id'));

  Future<Vehicle> createVehicle(Vehicle vehicle) async =>
      Vehicle.fromJson(await _api.post('/vehicles', vehicle.toJson()));

  Future<Vehicle> updateVehicle(Vehicle vehicle) async => Vehicle.fromJson(
    await _api.put('/vehicles/${vehicle.id}', vehicle.toJson()),
  );

  Future<void> deleteVehicle(String id) async {
    await _api.delete('/vehicles/$id');
  }

  Future<Vehicle> setDefault(String id) async =>
      Vehicle.fromJson(await _api.post('/vehicles/$id/default'));

  Future<Vehicle> uploadPhoto({
    required String vehicleId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async => Vehicle.fromJson(
    await _api.uploadMultipart(
      path: '/vehicles/$vehicleId/photos',
      fieldName: 'photo',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    ),
  );

  Future<Vehicle> setPrimaryPhoto({
    required String vehicleId,
    required String photoId,
  }) async => Vehicle.fromJson(
    await _api.post('/vehicles/$vehicleId/photos/$photoId/primary'),
  );

  Future<Uint8List> getPhotoBytes(String path) => _api.getBytes(path);

  Future<void> deletePhoto({
    required String vehicleId,
    required String photoId,
  }) async {
    await _api.delete('/vehicles/$vehicleId/photos/$photoId');
  }
}
