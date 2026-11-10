import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_management_service.dart';
import '../theme.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';
import 'preferences_page.dart';
import 'sanctions_page.dart';
import 'emergency_contacts_page.dart';
import 'support/support_page.dart';
import 'welcome_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onOpenSupport});

  final VoidCallback? onOpenSupport;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String? _role;
  bool _loading = false;
  bool _photoLoading = false;
  Future<Uint8List>? _photoFuture;

  UserProfile? get _user => AuthService.instance.currentUser.value;

  @override
  void initState() {
    super.initState();
    final user = _user;
    if (user != null) {
      _fullName.text = user.fullName;
      _phone.text = user.phone;
      _email.text = user.email;
      _role = user.role;
      if (user.hasProfilePhoto) {
        _photoFuture = UserManagementService.instance.getProfilePhoto();
      }
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _validateName(String? value) =>
      value == null || value.trim().isEmpty ? 'Name is required.' : null;

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone is required.';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 ||
        digits.length > 15 ||
        !RegExp(r'^\+?[0-9][0-9\s().-]{5,19}$').hasMatch(value.trim())) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
        ? null
        : 'Enter a valid email address.';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == null) return;

    setState(() => _loading = true);
    try {
      await AuthService.instance.updateProfile(
        fullName: _fullName.text,
        phone: _phone.text,
        email: _email.text,
        role: _role!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
        Navigator.of(context).pop();
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

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    setState(() => _photoLoading = true);
    try {
      final extension = image.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      await UserManagementService.instance.uploadProfilePhoto(
        bytes: await image.readAsBytes(),
        fileName: image.name,
        mimeType: mimeType,
      );
      final user = await AuthService.instance.refreshProfile();
      if (mounted) {
        setState(
          () => _photoFuture = user.hasProfilePhoto
              ? UserManagementService.instance.getProfilePhoto()
              : null,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoLoading = true);
    try {
      await UserManagementService.instance.deleteProfilePhoto();
      await AuthService.instance.refreshProfile();
      if (mounted) setState(() => _photoFuture = null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This permanently deletes your account and profile data. Enter your password to continue.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, password.text.isNotEmpty),
            child: const Text(
              'Delete account',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    final enteredPassword = password.text;
    password.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.deleteAccount(enteredPassword);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
          (_) => false,
        );
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
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: const Center(child: Text('Your profile is unavailable.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Center(child: _buildAvatar(user.hasProfilePhoto)),
                  const SizedBox(height: 12),
                  Text(
                    'Your account details',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  _statusCard(user.status, user.statusUntil),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.tune_rounded,
                            color: carShareGreen,
                          ),
                          title: const Text('Preferences'),
                          subtitle: const Text(
                            'Language, saved places, and ride preferences',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PreferencesPage(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.contact_phone_outlined,
                            color: carShareGreen,
                          ),
                          title: const Text('Emergency contacts'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const EmergencyContactsPage(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.history,
                            color: carShareGreen,
                          ),
                          title: const Text('Sanction history'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SanctionsPage(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.support_agent_outlined,
                            color: carShareGreen,
                          ),
                          title: const Text('Support'),
                          subtitle: const Text(
                            'Report a problem or view tickets',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              widget.onOpenSupport ??
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SupportPage(),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  CarShareTextField(
                    controller: _fullName,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    validator: _validateName,
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
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 14),
                  if (_role == 'admin')
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                      child: const Text('Administrator'),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'passenger',
                          child: Text('Ride as passenger'),
                        ),
                        DropdownMenuItem(
                          value: 'driver',
                          child: Text('Drive & share'),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) => setState(() => _role = value),
                      validator: (value) =>
                          value == null ? 'Please select a role.' : null,
                    ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F8F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          color: carShareGreen,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Member since ${_formatDate(user.createdAt)}',
                          style: const TextStyle(color: Color(0xFF718096)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Save changes',
                    loading: _loading,
                    onPressed: _saveProfile,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _deleteAccount,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Delete account',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => date.toIso8601String().substring(0, 10);

  Widget _buildAvatar(bool hasPhoto) => Stack(
    clipBehavior: Clip.none,
    children: [
      CircleAvatar(
        radius: 42,
        backgroundColor: const Color(0xFFD1FAE5),
        child: _photoFuture == null
            ? const Icon(Icons.person_rounded, color: carShareGreen, size: 46)
            : FutureBuilder<Uint8List>(
                future: _photoFuture,
                builder: (context, snapshot) => snapshot.hasData
                    ? ClipOval(
                        child: Image.memory(
                          snapshot.data!,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: carShareGreen,
                        size: 46,
                      ),
              ),
      ),
      Positioned(
        right: -4,
        bottom: -4,
        child: IconButton.filled(
          tooltip: _photoLoading ? 'Uploading photo' : 'Change profile photo',
          onPressed: _photoLoading ? null : _pickPhoto,
          icon: _photoLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.camera_alt_outlined, size: 18),
        ),
      ),
      if (hasPhoto)
        Positioned(
          left: -4,
          bottom: -4,
          child: IconButton.filledTonal(
            tooltip: 'Remove profile photo',
            onPressed: _photoLoading ? null : _removePhoto,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ),
    ],
  );

  Widget _statusCard(String status, DateTime? until) {
    final label = switch (status) {
      'WARNING' => 'Warning',
      'SUSPENDED' => 'Suspended',
      'BANNED' => 'Banned',
      _ => 'Active',
    };
    final description = status == 'SUSPENDED' && until != null
        ? 'Restricted until ${_formatDate(until.toLocal())}'
        : status == 'WARNING'
        ? 'Please review your account conduct.'
        : status == 'BANNED'
        ? 'Contact CarShare support for assistance.'
        : 'Your account is in good standing.';
    return Card(
      child: ListTile(
        leading: Icon(
          status == 'ACTIVE'
              ? Icons.verified_user_outlined
              : Icons.warning_amber_rounded,
          color: status == 'ACTIVE' ? carShareGreen : Colors.orange,
        ),
        title: Text('Account status: $label'),
        subtitle: Text(description),
      ),
    );
  }
}
