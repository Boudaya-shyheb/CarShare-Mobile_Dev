import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../navigation.dart';
import '../pages/reset_password_page.dart';

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _pendingResetToken;
  String? _recentlyHandledToken;
  DateTime? _recentlyHandledAt;

  void initialize() {
    if (_subscription != null) return;
    _subscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    }, onError: (Object _, StackTrace _) {});
    unawaited(_handleInitialUri());
  }

  Future<void> _handleInitialUri() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleUri(uri);
    } catch (_) {
      // Stream links still work if reading the initial link is unavailable.
    }
  }

  void openPendingLink() {
    final token = _pendingResetToken;
    if (token == null) return;
    _pendingResetToken = null;
    _showResetPage(token);
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'carshare' || uri.host != 'reset-password') return;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;

    final now = DateTime.now();
    if (token == _recentlyHandledToken &&
        _recentlyHandledAt != null &&
        now.difference(_recentlyHandledAt!) < const Duration(seconds: 2)) {
      return;
    }
    _recentlyHandledToken = token;
    _recentlyHandledAt = now;

    if (carShareNavigatorKey.currentState == null) {
      _pendingResetToken = token;
      return;
    }
    _showResetPage(token);
  }

  void _showResetPage(String token) {
    carShareNavigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(builder: (_) => ResetPasswordPage(token: token)),
    );
  }
}
