import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';
import 'reset_password_page.dart';
import 'sign_up_page.dart';
import 'welcome_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  static const routeName = '/sign-in';

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _service = AuthService.instance;
  bool _loading = false;
  bool _sendingReset = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _service.signIn(email: _email.text, password: _password.text);
      final user = _service.currentUser.value;
      if (!mounted || user == null) return;

      // Pop back to the _AuthenticationGate instead of pushing a screen: the gate listens to
      // AuthService.currentUser and builds MainShell (or the admin screen) for the signed-in
      // user. Pushing HomePage here bypassed it, so the reservation shell never appeared.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final emailError = _validateEmail(_email.text);
    if (emailError != null) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() => _sendingReset = true);
    try {
      await _service.sendPasswordReset(_email.text);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ResetPasswordPage(token: '', email: _email.text.trim()),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
          (_) => false,
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled_rounded,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to find or offer a ride.',
                    style: TextStyle(color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 28),
                  CarShareTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  CarShareTextField(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Password is required.'
                        : null,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _sendingReset ? null : _resetPassword,
                      child: _sendingReset
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'Sign In',
                    loading: _loading,
                    onPressed: _signIn,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('Don’t have an account? '),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, SignUpPage.routeName),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
