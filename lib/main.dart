import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinkService.instance.initialize();
  runApp(const CarShareApp());
  unawaited(AuthService.instance.restoreSession());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    DeepLinkService.instance.openPendingLink();
  });
}
