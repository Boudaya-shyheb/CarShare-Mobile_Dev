import 'dart:typed_data';

import '../models/user_preferences.dart';
import '../models/user_sanction.dart';
import 'api_client.dart';

class UserManagementService {
  UserManagementService._();
  static final instance = UserManagementService._();
  final ApiClient _api = ApiClient.instance;

  Future<UserPreferences> getPreferences() async =>
      UserPreferences.fromJson(await _api.get('/users/me/preferences'));

  Future<UserPreferences> updatePreferences(
    UserPreferences preferences,
  ) async => UserPreferences.fromJson(
    await _api.put('/users/me/preferences', preferences.toJson()),
  );

  Future<List<UserSanction>> getSanctions() async =>
      (await _api.getList('/users/me/sanctions'))
          .map(UserSanction.fromJson)
          .toList(growable: false);

  Future<Uint8List> getProfilePhoto() => _api.getPhotoBytes();

  Future<void> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) => _api.uploadPhoto(bytes: bytes, fileName: fileName, mimeType: mimeType);

  Future<void> deleteProfilePhoto() => _api.deletePhoto();

  Future<List<Map<String, dynamic>>> getEmergencyContacts() =>
      _api.getList('/users/me/emergency-contacts');

  Future<void> saveEmergencyContact({
    String? id,
    required String name,
    required String phone,
    required String relationship,
  }) async {
    final body = {'name': name, 'phone': phone, 'relationship': relationship};
    if (id == null) {
      await _api.post('/users/me/emergency-contacts', body);
    } else {
      await _api.put('/users/me/emergency-contacts/$id', body);
    }
  }

  Future<void> deleteEmergencyContact(String id) async {
    await _api.delete('/users/me/emergency-contacts/$id');
  }
}
