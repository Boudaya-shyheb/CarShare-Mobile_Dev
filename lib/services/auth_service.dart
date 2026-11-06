import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import 'api_client.dart';
import 'local_database.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final ValueNotifier<UserProfile?> currentUser = ValueNotifier(null);
  final ValueNotifier<bool> isRestoringSession = ValueNotifier(true);
  final ApiClient _api = ApiClient.instance;
  final LocalDatabase _localDatabase = LocalDatabase.instance;
  int _sessionRevision = 0;

  Future<void> restoreSession() async {
    final revision = _sessionRevision;
    final token = await _api.readToken();
    if (revision != _sessionRevision) return;
    if (token == null) {
      isRestoringSession.value = false;
      return;
    }

    UserProfile? cachedProfile;
    try {
      cachedProfile = await _localDatabase.getProfile();
      if (revision != _sessionRevision) return;
      if (cachedProfile != null) {
        currentUser.value = cachedProfile;
        isRestoringSession.value = false;
      }
    } catch (_) {
      // A damaged or unavailable local cache must not block server sign-in.
    }

    try {
      final profile = UserProfile.fromJson(await _api.get('/users/me'));
      if (revision != _sessionRevision) return;
      currentUser.value = profile;
      await _cacheProfile(profile);
    } on ApiException catch (error) {
      if (revision != _sessionRevision) return;
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _api.clearToken();
        await _clearCachedProfile();
        currentUser.value = null;
      } else if (cachedProfile != null) {
        currentUser.value = cachedProfile;
      }
    } catch (_) {
      if (revision != _sessionRevision) return;
      if (cachedProfile != null) currentUser.value = cachedProfile;
    } finally {
      isRestoringSession.value = false;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    _sessionRevision++;
    await _saveAuthResponse(
      await _api.post('/auth/signin', {
        'email': email.trim(),
        'password': password,
      }),
    );
  }

  Future<void> signUp({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required String confirmPassword,
    required String role,
  }) async {
    _sessionRevision++;
    await _saveAuthResponse(
      await _api.post('/auth/signup', {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'password': password,
        'confirmPassword': confirmPassword,
        'role': role,
      }),
    );
  }

  Future<void> _saveAuthResponse(Map<String, dynamic> response) async {
    await _api.saveToken(response['accessToken'] as String);
    currentUser.value = UserProfile.fromJson(
      response['user'] as Map<String, dynamic>,
    );
    await _cacheProfile(currentUser.value!);
  }

  Future<void> sendPasswordReset(String email) async {
    await _api.post('/auth/forgot-password', {'email': email.trim()});
  }

  Future<void> resetPassword({
    String email = '',
    required String token,
    required String newPassword,
  }) async {
    await _api.post('/auth/reset-password', {
      if (email.isNotEmpty) 'email': email.trim(),
      'token': token,
      'newPassword': newPassword,
    });
  }

  Future<UserProfile> updateProfile({
    required String fullName,
    required String phone,
    required String email,
    required String role,
  }) async {
    final profile = UserProfile.fromJson(
      await _api.put('/users/me', {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'role': role,
      }),
    );
    currentUser.value = profile;
    await _cacheProfile(profile);
    return profile;
  }

  Future<UserProfile> refreshProfile() async {
    final profile = UserProfile.fromJson(await _api.get('/users/me'));
    currentUser.value = profile;
    await _cacheProfile(profile);
    return profile;
  }

  Future<void> deleteAccount(String password) async {
    await _api.delete('/users/me', {'password': password});
    _sessionRevision++;
    await _api.clearToken();
    await _clearCachedProfile();
    currentUser.value = null;
  }

  Future<void> signOut() async {
    _sessionRevision++;
    try {
      await _api.post('/auth/signout');
    } catch (_) {
      // Always end the local session if the API cannot be reached.
    } finally {
      await _api.clearToken();
      await _clearCachedProfile();
      currentUser.value = null;
    }
  }

  Future<void> _cacheProfile(UserProfile profile) async {
    try {
      await _localDatabase.saveProfile(profile);
    } catch (_) {
      // Local caching is best effort; the backend session remains authoritative.
    }
  }

  Future<void> _clearCachedProfile() async {
    try {
      await _localDatabase.clearProfile();
    } catch (_) {
      // A cache cleanup failure must not keep the user signed in.
    }
  }
}

String authErrorMessage(Object error) => error is ApiException
    ? error.message
    : 'We could not complete your request. Please try again.';
