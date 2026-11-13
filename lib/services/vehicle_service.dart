import 'package:flutter/foundation.dart';

import '../models/vehicle.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'local_database.dart';

class VehicleService {
  VehicleService._();
  static final instance = VehicleService._();

  final ApiClient _api = ApiClient.instance;
  final LocalDatabase _localDatabase = LocalDatabase.instance;

  Future<List<Vehicle>> getVehicles() async {
    final userId = AuthService.instance.currentUser.value?.id;
    try {
      final vehicles = (await _api.getList('/vehicles'))
          .map(Vehicle.fromJson)
          .toList(growable: false);
      if (userId != null) await _saveVehicles(userId, vehicles);
      return vehicles;
    } catch (error) {
      if (userId != null) {
        try {
          final cached = await _localDatabase.getVehicles(userId);
          if (cached.isNotEmpty) return cached;
        } catch (cacheError, stackTrace) {
          debugPrint(
            'Could not read the vehicle cache: $cacheError\n$stackTrace',
          );
        }
      }
      rethrow;
    }
  }

  Future<Vehicle> getVehicle(String id) async {
    final userId = AuthService.instance.currentUser.value?.id;
    try {
      return await _cacheResponse(_api.get('/vehicles/$id'));
    } catch (error, stackTrace) {
      if (userId != null) {
        try {
          final cached = await _localDatabase.getVehicle(userId, id);
          if (cached != null) return cached;
        } catch (cacheError, cacheStackTrace) {
          debugPrint(
            'Could not read the vehicle cache: $cacheError\n$cacheStackTrace',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Vehicle> createVehicle(Vehicle vehicle) =>
      _cacheResponse(_api.post('/vehicles', vehicle.toJson()));

  Future<Vehicle> updateVehicle(Vehicle vehicle) =>
      _cacheResponse(_api.put('/vehicles/${vehicle.id}', vehicle.toJson()));

  Future<void> deleteVehicle(String id) async {
    await _api.delete('/vehicles/$id');
    final userId = AuthService.instance.currentUser.value?.id;
    if (userId != null) await _deleteCachedVehicle(userId, id);
  }

  Future<Vehicle> setDefault(String id) =>
      _cacheResponse(_api.post('/vehicles/$id/default'));

  Future<Vehicle> uploadPhoto({
    required String vehicleId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) => _cacheResponse(
    _api.uploadMultipart(
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
  }) =>
      _cacheResponse(_api.post('/vehicles/$vehicleId/photos/$photoId/primary'));

  Future<Uint8List> getPhotoBytes(String path) => _api.getBytes(path);

  Future<void> deletePhoto({
    required String vehicleId,
    required String photoId,
  }) async {
    await _api.delete('/vehicles/$vehicleId/photos/$photoId');
    final userId = AuthService.instance.currentUser.value?.id;
    if (userId == null) return;
    try {
      await _cacheResponse(_api.get('/vehicles/$vehicleId'));
    } catch (error, stackTrace) {
      debugPrint('Could not refresh the vehicle cache: $error\n$stackTrace');
    }
  }

  Future<Vehicle> _cacheResponse(Future<Map<String, dynamic>> response) async {
    final vehicle = Vehicle.fromJson(await response);
    final userId = AuthService.instance.currentUser.value?.id;
    if (userId != null) await _saveVehicle(userId, vehicle);
    return vehicle;
  }

  Future<void> _saveVehicles(String userId, List<Vehicle> vehicles) async {
    try {
      await _localDatabase.saveVehicles(userId, vehicles);
    } catch (error, stackTrace) {
      debugPrint('Could not save the vehicle cache: $error\n$stackTrace');
    }
  }

  Future<void> _saveVehicle(String userId, Vehicle vehicle) async {
    try {
      await _localDatabase.saveVehicle(userId, vehicle);
    } catch (error, stackTrace) {
      debugPrint('Could not save the vehicle cache: $error\n$stackTrace');
    }
  }

  Future<void> _deleteCachedVehicle(String userId, String vehicleId) async {
    try {
      await _localDatabase.deleteCachedVehicle(userId, vehicleId);
    } catch (error, stackTrace) {
      debugPrint('Could not delete the vehicle cache: $error\n$stackTrace');
    }
  }
}
