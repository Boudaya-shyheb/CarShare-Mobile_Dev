import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/labeled_text_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/round_back_button.dart';
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
    (route) => route.isFirst,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: roundBackAppBar(context),
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
        const Text(
          'Choose a new password',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
            color: carShareText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.token.isEmpty
              ? 'Enter the 6-digit code from your email and choose a new password.'
              : 'Your password must contain at least 8 characters.',
          style: const TextStyle(color: carShareMuted, fontSize: 15),
        ),
        const SizedBox(height: 28),
        if (widget.token.isEmpty) ...[
          LabeledTextField(
            controller: _token,
            label: 'Email reset code',
            hintText: '6-digit code',
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
          const SizedBox(height: 18),
        ],
        LabeledTextField(
          controller: _password,
          label: 'New password',
          hintText: 'At least 8 characters',
          obscureText: true,
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Password is required.';
            if (value.length < 8) return 'Use at least 8 characters.';
            return null;
          },
        ),
        const SizedBox(height: 18),
        LabeledTextField(
          controller: _confirmPassword,
          label: 'Confirm new password',
          hintText: 'Type it again',
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
      const Icon(Icons.check_circle, color: carShareGreen, size: 52),
      const SizedBox(height: 20),
      const Text(
        'Password updated',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
          color: carShareText,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Your password has been reset. You can now sign in.',
        style: TextStyle(color: carShareMuted, fontSize: 15),
      ),
      const SizedBox(height: 24),
      PrimaryButton(label: 'Go to Sign In', onPressed: _goToSignIn),
    ],
  );
}
