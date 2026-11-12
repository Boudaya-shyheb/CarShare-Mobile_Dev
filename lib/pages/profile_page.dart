import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/driver_license_ocr_service.dart';
import '../services/user_management_service.dart';
import '../theme.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';
import 'preferences_page.dart';
import 'sanctions_page.dart';
import 'emergency_contacts_page.dart';
import 'lost_and_found_page.dart';
import 'my_vehicles_page.dart';
import 'support/support_page.dart';
import 'welcome_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

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
  bool _licenseLoading = false;
  Future<Uint8List>? _photoFuture;
  final ExpansibleController _editTileController = ExpansibleController();
  final GlobalKey _editTileKey = GlobalKey();

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
    _editTileController.dispose();
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

  Future<void> _scanDriverLicense() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 68,
    );
    if (image == null || !mounted) return;
    setState(() => _licenseLoading = true);
    try {
      final candidates = await DriverLicenseOcrService()
          .readPossibleExpiryDates(image.path);
      if (!mounted) return;
      final today = DateUtils.dateOnly(DateTime.now());
      DateTime? detected;
      for (final date in candidates) {
        if (!date.isBefore(today)) {
          detected = date;
          break;
        }
      }
      final expiry = await showDatePicker(
        context: context,
        initialDate:
            detected ?? DateTime(today.year + 1, today.month, today.day),
        firstDate: today,
        lastDate: DateTime(today.year + 30),
        helpText: detected == null
            ? 'Select the license expiry date'
            : 'Confirm the expiry date read from the license',
      );
      if (expiry == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const ApiException(
          'The license image is larger than 2 MB. Please scan it again closer and in better light.',
        );
      }
      final ext = image.name.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      await UserManagementService.instance.submitDriverLicense(
        bytes: bytes,
        fileName: image.name,
        mimeType: mime,
        expiryDate: expiry,
      );
      await AuthService.instance.refreshProfile();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('License submitted for admin review.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      try {
        final localImage = File(image.path);
        if (await localImage.exists()) await localImage.delete();
      } catch (_) {
        // The temporary camera file is best-effort cleanup.
      }
      if (mounted) setState(() => _licenseLoading = false);
    }
  }

  Future<void> _openEditProfile() async {
    _editTileController.expand();
    await WidgetsBinding.instance.endOfFrame;
    final tileContext = _editTileKey.currentContext;
    if (tileContext != null && tileContext.mounted) {
      await Scrollable.ensureVisible(
        tileContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
      backgroundColor: carShareBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildHeader(user),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      children: [
                        _statusCard(user.status, user.statusUntil),
                        const SizedBox(height: 12),
                        if (user.role.toLowerCase() == 'driver') ...[
                          _driverLicenseCard(user),
                          const SizedBox(height: 12),
                        ],
                        Card(
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              carShareCardRadius,
                            ),
                            side: const BorderSide(color: carShareBorder),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              // Vehicles belong to drivers only; a passenger never sees this row.
                              if (user.role.toLowerCase() == 'driver') ...[
                                _menuRow(
                                  icon: Icons.directions_car_outlined,
                                  title: 'My vehicles',
                                  subtitle: 'Add or manage your vehicles',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const MyVehiclesPage(),
                                    ),
                                  ),
                                ),
                                _rowDivider,
                              ],
                              _menuRow(
                                icon: Icons.tune_rounded,
                                title: 'Preferences',
                                subtitle: 'Language, saved places, and ride preferences',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const PreferencesPage(),
                                  ),
                                ),
                              ),
                              _rowDivider,
                              _menuRow(
                                icon: Icons.contact_phone_outlined,
                                title: 'Emergency contacts',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const EmergencyContactsPage(),
                                  ),
                                ),
                              ),
                              _rowDivider,
                              _menuRow(
                                icon: Icons.history,
                                title: 'Sanction history',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SanctionsPage(),
                                  ),
                                ),
                              ),
                              _rowDivider,
                              _menuRow(
                                icon: Icons.search_rounded,
                                title: 'Lost & Found',
                                subtitle: 'Report or follow a lost item',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => LostAndFoundPage(
                                      key: ValueKey(user.id),
                                      userId: user.id,
                                    ),
                                  ),
                                ),
                              ),
                              _rowDivider,
                              _menuRow(
                                icon: Icons.support_agent_outlined,
                                title: 'Help & support',
                                subtitle: 'Report a problem or view tickets',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SupportPage(),
                                  ),
                                ),
                              ),
                              _rowDivider,
                              // The existing edit form, unchanged, behind one row. It stays built
                              // while collapsed so the Form key and the controllers keep working.
                              ExpansionTile(
                                key: _editTileKey,
                                controller: _editTileController,
                                maintainState: true,
                                shape: const Border(),
                                collapsedShape: const Border(),
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  20,
                                ),
                                leading: _menuIcon(Icons.edit_outlined),
                                title: const Text(
                                  'Edit profile',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                children: [
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
                                        prefixIcon: Icon(
                                          Icons.admin_panel_settings_outlined,
                                        ),
                                      ),
                                      child: const Text('Administrator'),
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      initialValue: _role,
                                      decoration: const InputDecoration(
                                        labelText: 'Role',
                                        prefixIcon: Icon(
                                          Icons.directions_car_outlined,
                                        ),
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
                                          : (value) =>
                                                setState(() => _role = value),
                                      validator: (value) => value == null
                                          ? 'Please select a role.'
                                          : null,
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
                                          style: const TextStyle(
                                            color: Color(0xFF718096),
                                          ),
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
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Delete account',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                              _rowDivider,
                              _menuRow(
                                icon: Icons.logout_rounded,
                                title: 'Log out',
                                danger: true,
                                onTap: _signOut,
                              ),
                            ],
                          ),
                        ),
                      ],
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

  static const _rowDivider = Divider(
    height: 1,
    indent: 72,
    color: carShareBorder,
  );

  Widget _menuIcon(IconData icon, {bool danger = false}) => CircleAvatar(
    radius: 20,
    backgroundColor: danger ? const Color(0xFFFEE2E2) : carShareTint,
    child: Icon(icon, size: 20, color: danger ? carShareDanger : carShareGreen),
  );

  Widget _menuRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    leading: _menuIcon(icon, danger: danger),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: danger ? carShareDanger : carShareText,
      ),
    ),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: danger ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  String _roleLabel(String role) => switch (role.toLowerCase()) {
    'driver' => 'Driver',
    'admin' => 'Administrator',
    _ => 'Passenger',
  };

  /// Profile summary styled to match the reference screen.
  Widget _buildHeader(UserProfile user) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [carShareGreen, carShareGreenDark],
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Edit profile',
              onPressed: _openEditProfile,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: _buildAvatar(user.hasProfilePhoto),
        ),
        const SizedBox(height: 8),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.transparent),
          child: Text(
            '${_roleLabel(user.role)} · Member since ${user.createdAt.year}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  /// Same sign-out MainShell used to draw over this page's AppBar; the gate in app.dart swaps
  /// the shell for the Welcome page once the session ends.
  Future<void> _signOut() async {
    try {
      await AuthService.instance.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
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

  Widget _driverLicenseCard(UserProfile user) {
    final pending = user.driverLicenseStatus == 'PENDING_REVIEW';
    final approved = user.driverLicenseStatus == 'APPROVED';
    final label = switch (user.driverLicenseStatus) {
      'PENDING_REVIEW' => 'Waiting for admin review',
      'APPROVED' => 'Verified by admin',
      'REJECTED' => 'Needs a new scan',
      _ => 'Not submitted',
    };
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(carShareCardRadius),
        side: const BorderSide(color: carShareBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, color: carShareGreen),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Driver license',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: approved ? carShareGreen : Colors.blueGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (user.driverLicenseExpiry != null) ...[
              const SizedBox(height: 8),
              Text('Expiry date: ${_formatDate(user.driverLicenseExpiry!)}'),
            ],
            if ((user.driverLicenseReviewReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Admin note: ${user.driverLicenseReviewReason}',
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'The expiry date is read on your phone. The license image is visible to admins only and is deleted after their decision.',
              style: TextStyle(color: Color(0xFF718096), fontSize: 12),
            ),
            if (!pending) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _licenseLoading ? null : _scanDriverLicense,
                icon: _licenseLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _licenseLoading
                      ? 'Reading license…'
                      : user.driverLicenseStatus == 'REJECTED'
                      ? 'Scan again'
                      : 'Scan driver license',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
