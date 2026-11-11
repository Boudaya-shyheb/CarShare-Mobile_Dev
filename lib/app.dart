import 'package:flutter/material.dart';

import 'models/user_profile.dart';
import 'navigation.dart';
import 'pages/main_shell.dart';
import 'pages/admin_dashboard_page.dart';
import 'pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';
import 'pages/welcome_page.dart';
import 'services/auth_service.dart';
import 'theme.dart';

class CarShareApp extends StatelessWidget {
  const CarShareApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: carShareNavigatorKey,
    title: 'CarShare',
    debugShowCheckedModeBanner: false,
    theme: carShareTheme,
    home: const _AuthenticationGate(),
    routes: {
      SignInPage.routeName: (_) => const SignInPage(),
      SignUpPage.routeName: (_) => const SignUpPage(),
    },
  );
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: AuthService.instance.isRestoringSession,
    builder: (context, isRestoring, _) => isRestoring
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : ValueListenableBuilder<UserProfile?>(
            valueListenable: AuthService.instance.currentUser,
            builder: (context, user, _) => user == null
                ? const WelcomePage()
                : user.role == 'admin'
                ? const AdminDashboardPage()
                : MainShell(user: user),
          ),
  );
}
