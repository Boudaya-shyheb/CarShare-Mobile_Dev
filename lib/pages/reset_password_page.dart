import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';
import 'sign_in_page.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.token, this.email = ''});

  final String token;
  final String email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _auth = AuthService.instance;
  bool _loading = false;
  String? _errorMessage;
  bool _completed = false;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _auth.resetPassword(
        email: widget.email,
        token: widget.token.isEmpty ? _token.text.trim() : widget.token,
        newPassword: _password.text,
      );
      await _auth.signOut();
      if (mounted) setState(() => _completed = true);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToSignIn() => Navigator.of(context).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(builder: (_) => const SignInPage()),
    (_) => false,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _completed ? _successContent() : _formContent(),
          ),
        ),
      ),
    ),
  );

  Widget _formContent() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a new password',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          widget.token.isEmpty
              ? 'Enter the 6-digit code from your email and choose a new password.'
              : 'Your password must contain at least 8 characters.',
        ),
        const SizedBox(height: 28),
        if (widget.token.isEmpty) ...[
          CarShareTextField(
            controller: _token,
            label: 'Email reset code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter the code from your email.';
              }
              if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
                return 'Enter the 6-digit code from your email.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
        ],
        CarShareTextField(
          controller: _password,
          label: 'New password',
          icon: Icons.lock_outline,
          obscureText: true,
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Password is required.';
            if (value.length < 8) return 'Use at least 8 characters.';
            return null;
          },
        ),
        const SizedBox(height: 16),
        CarShareTextField(
          controller: _confirmPassword,
          label: 'Confirm new password',
          icon: Icons.lock_reset,
          obscureText: true,
          textInputAction: TextInputAction.done,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your password.';
            }
            if (value != _password.text) return 'Passwords do not match.';
            return null;
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Update password',
          loading: _loading,
          onPressed: _resetPassword,
        ),
      ],
    ),
  );

  Widget _successContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check_circle, color: Color(0xFF059669), size: 52),
      const SizedBox(height: 20),
      Text(
        'Password updated',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('Your password has been reset. You can now sign in.'),
      const SizedBox(height: 24),
      PrimaryButton(label: 'Go to Sign In', onPressed: _goToSignIn),
    ],
  );
}
