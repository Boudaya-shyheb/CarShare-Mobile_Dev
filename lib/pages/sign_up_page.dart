import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/labeled_text_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/round_back_button.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  static const routeName = '/sign-up';

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _service = AuthService.instance;
  String? _role;
  bool _showRoleError = false;
  bool _loading = false;
  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String? _required(String? value, String field) =>
      value == null || value.trim().isEmpty ? '$field is required.' : null;

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone is required.';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      return 'Enter a valid phone number.';
    }
    if (!RegExp(r'^\+?[0-9][0-9\s().-]{5,19}$').hasMatch(value.trim())) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == null) {
      setState(() => _showRoleError = true);
      return;
    }
    setState(() => _loading = true);
    try {
      await _service.signUp(
        fullName: _fullName.text,
        phone: _phone.text,
        email: _email.text,
        password: _password.text,
        confirmPassword: _confirmPassword.text,
        role: _role!,
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: roundBackAppBar(
      context,
      onBack: () => Navigator.maybePop(context),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: carShareTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Join CarShare',
          style: TextStyle(
            color: carShareGreen,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          // The whole form scrolls, so Create account can always be reached, with or
          // without the keyboard open; dragging the form closes the keyboard.
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create your account',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                      color: carShareText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tell us who you are and how you’ll use CarShare.',
                    style: TextStyle(color: carShareMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  LabeledTextField(
                    controller: _fullName,
                    label: 'Full name',
                    hintText: 'Your full name',
                    validator: (v) => _required(v, 'Name'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  LabeledTextField(
                    controller: _phone,
                    label: 'Phone',
                    hintText: '+216 55 123 456',
                    validator: _validatePhone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  LabeledTextField(
                    controller: _email,
                    label: 'Email',
                    hintText: 'you@example.com',
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  LabeledTextField(
                    controller: _password,
                    label: 'Password',
                    hintText: 'At least 8 characters',
                    validator: _validatePassword,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  LabeledTextField(
                    controller: _confirmPassword,
                    label: 'Confirm password',
                    hintText: 'Type it again',
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password.';
                      }
                      if (value != _password.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'I want to…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: carShareText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _RoleCard(
                            title: 'Ride as passenger',
                            subtitle: 'Find & book seats',
                            icon: Icons.groups_rounded,
                            selected: _role == 'passenger',
                            onTap: () => setState(() {
                              _role = 'passenger';
                              _showRoleError = false;
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleCard(
                            title: 'Drive & share',
                            subtitle: 'Offer seats on my route',
                            icon: Icons.directions_car_outlined,
                            selected: _role == 'driver',
                            onTap: () => setState(() {
                              _role = 'driver';
                              _showRoleError = false;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showRoleError && _role == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 7, left: 4),
                      child: Text(
                        'Please select a role.',
                        style: TextStyle(color: carShareDanger, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Create account',
                    loading: _loading,
                    onPressed: _createAccount,
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'By continuing, you agree to our Terms & Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: carShareMuted, fontSize: 12),
                    ),
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

/// One of the two role choices: an icon tile, a check badge, the title and a short line. The
/// chosen card turns mint with a green border, like the mockup.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? carShareTint : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? carShareGreen : carShareBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? carShareGreen : carShareBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? Colors.white : carShareMuted,
                  ),
                ),
                const Spacer(),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 24,
                  color: selected ? carShareGreen : carShareBorder,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: carShareText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: carShareMuted),
            ),
          ],
        ),
      ),
    ),
  );
}
