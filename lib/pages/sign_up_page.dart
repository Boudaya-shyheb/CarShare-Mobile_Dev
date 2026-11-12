import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';

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
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          'Join CarShare',
                          style: TextStyle(
                            color: carShareGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Create your account',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Tell us a little about yourself.',
                    style: TextStyle(color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 22),
                  CarShareTextField(
                    controller: _fullName,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    validator: (v) => _required(v, 'Name'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CarShareTextField(
                    controller: _phone,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    validator: _validatePhone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CarShareTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    validator: _validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CarShareTextField(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    validator: _validatePassword,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CarShareTextField(
                    controller: _confirmPassword,
                    label: 'Confirm Password',
                    icon: Icons.lock_reset_outlined,
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
                  const SizedBox(height: 20),
                  Text(
                    'I want to...',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
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
                          icon: Icons.directions_car_filled_rounded,
                          selected: _role == 'driver',
                          onTap: () => setState(() {
                            _role = 'driver';
                            _showRoleError = false;
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (_showRoleError && _role == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 7, left: 4),
                      child: Text(
                        'Please select a role.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: 'Create account',
                    loading: _loading,
                    onPressed: _createAccount,
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'By continuing, you agree to our Terms & Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF87939B), fontSize: 11),
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
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        height: 116,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFD1FAE5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? carShareGreen : const Color(0xFFDCE4E9),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected ? carShareGreen : const Color(0xFF718096),
                ),
                const Spacer(),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 19,
                  color: selected ? carShareGreen : const Color(0xFFCBD5E0),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
            ),
          ],
        ),
      ),
    ),
  );
}
