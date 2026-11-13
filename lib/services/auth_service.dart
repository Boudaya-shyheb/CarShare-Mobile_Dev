import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

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
  bool _googleSignInInitialized = false;
  String? _pendingGoogleToken;

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
    try {
      if (!_googleSignInInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: serverClientId.isEmpty ? null : serverClientId,
        );
        _googleSignInInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const ApiException(
          'Google did not return a sign-in token. Check the Web OAuth client ID and Android SHA-1 configuration.',
        );
      }
      await _signInWithGoogleToken(token, phone: phone, role: role);
    } on GoogleSignInException catch (error) {
      final message = switch (error.code) {
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        GoogleSignInExceptionCode.clientConfigurationError => 'Google sign-in is misconfigured. Check the Web client ID, Android package name, and debug SHA-1.',
        GoogleSignInExceptionCode.providerConfigurationError => 'Google sign-in is unavailable on this device. Update Google Play services and try again.',
        GoogleSignInExceptionCode.uiUnavailable => 'Google sign-in could not open. Close other sign-in windows and try again.',
        _ =>
          'Google sign-in failed. Check the OAuth configuration and try again.',
      };
      throw ApiException(message, code: 'google_sign_in_${error.code.name}');
    }
  }

  Future<void> completeGoogleProfile({
    required String phone,
    required String role,
  }) async {
    final token = _pendingGoogleToken;
    if (token == null) {
      throw const ApiException('Please restart social sign-in.');
    }
    await _signInWithGoogleToken(token, phone: phone, role: role);
  }

  Future<void> _signInWithGoogleToken(
    String token, {
    String? phone,
    String? role,
  }) async {
    _sessionRevision++;
    try {
      await _saveAuthResponse(
        await _api.post('/auth/social/google', {
          'token': token,
          if (phone != null) 'phone': phone.trim(),
          'role': ?role,
        }),
      );
      _pendingGoogleToken = null;
    } on ApiException catch (error) {
      if (error.code == 'social_profile_required') {
        _pendingGoogleToken = token;
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
    }
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await _api.clearToken();
    } catch (_) {}
    await _clearCachedProfile();
    currentUser.value = null;
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

/// What to show for any failed request. The server already writes a plain sentence for every
/// account rule (banned, suspended, role switch, deletion); this only puts a suspension's end in
/// the phone's own time, so "until 13 Nov 2026 at 12:00 UTC" reads as the user's local time.
String authErrorMessage(Object error) {
  if (error is! ApiException) {
    return 'We could not complete your request. Please try again.';
  }
  final until = error.statusUntil;
  if (until != null) {
    final when = DateFormat('d MMM yyyy, HH:mm').format(until);
    if (error.code == 'account_suspended') {
      return 'Your account is suspended until $when, so you cannot make changes. '
          'You can still sign in and look around.';
    }
    if (error.code == 'delete_blocked_suspended') {
      return 'You cannot delete your account while it is suspended. The suspension ends $when.';
    }
  }
  return error.message;
}
