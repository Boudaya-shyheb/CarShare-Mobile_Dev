import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

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
  String? _pendingSocialProvider;
  String? _pendingSocialToken;

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

  Future<void> signInWithGoogle({String? phone, String? role}) async {
    const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('Google did not return a sign-in token. Check the Google app configuration.');
    }
    await _signInWithProvider('google', token, phone: phone, role: role);
  }

  Future<void> signInWithFacebook({String? phone, String? role}) async {
    const appId = String.fromEnvironment('FACEBOOK_APP_ID');
    if (appId.isEmpty) {
      throw const ApiException('Facebook sign-in needs the Meta App ID and Android setup before it can be used.');
    }
    final result = await FacebookAuth.instance.login(permissions: const ['email', 'public_profile']);
    final token = result.accessToken?.tokenString;
    if (result.status != LoginStatus.success || token == null || token.isEmpty) {
      if (result.status == LoginStatus.cancelled) return;
      throw ApiException(result.message ?? 'Facebook sign-in could not be completed.');
    }
    await _signInWithProvider('facebook', token, phone: phone, role: role);
  }

  Future<void> completeSocialProfile({required String phone, required String role}) async {
    final provider = _pendingSocialProvider;
    final token = _pendingSocialToken;
    if (provider == null || token == null) {
      throw const ApiException('Please restart social sign-in.');
    }
    await _signInWithProvider(provider, token, phone: phone, role: role);
  }

  Future<void> _signInWithProvider(String provider, String token, {String? phone, String? role}) async {
    _sessionRevision++;
    try {
      await _saveAuthResponse(await _api.post('/auth/social/$provider', {
        'token': token,
        if (phone != null) 'phone': phone.trim(),
        'role': ?role,
      }));
      _pendingSocialProvider = null;
      _pendingSocialToken = null;
    } on ApiException catch (error) {
      if (error.code == 'social_profile_required') {
        _pendingSocialProvider = provider;
        _pendingSocialToken = token;
      }
      rethrow;
    }
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
      try { await GoogleSignIn.instance.signOut(); } catch (_) { }
      try { await FacebookAuth.instance.logOut(); } catch (_) { }
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
