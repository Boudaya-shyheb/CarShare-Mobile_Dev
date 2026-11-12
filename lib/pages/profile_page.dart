import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/driver_license_ocr_service.dart';
import '../services/user_management_service.dart';
import '../theme.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/profile_stats_card.dart';
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

  /// The session restore (and a license review) can replace the signed-in user after this page
  /// was built, so rebuild when it changes. Typed text in the edit form is left alone.
  void _userChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AuthService.instance.currentUser.addListener(_userChanged);
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
    AuthService.instance.currentUser.removeListener(_userChanged);
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
                padding: EdgeInsets.zero,
                children: [
                  _buildHeader(user),
                  // Pulled up over the header's bottom edge (the header has that much extra
                  // padding): that is how the stats card overlaps it in the mockup.
                  Transform.translate(
                    offset: const Offset(0, -_headerOverlap),
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      children: [
                        const ProfileStatsCard(),
                        _statusCard(user.status, user.statusUntil),
                        const SizedBox(height: 12),
                        // Driver-license verification (drivers only), above the menu card.
                        if (user.role.toLowerCase() == 'driver') ...[
                          _driverLicenseCard(user),
                          const SizedBox(height: 12),
                        ],
                        Card(
                    color: Colors.white,
                    elevation: 4,
                    shadowColor: const Color(0x22000000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(carShareCardRadius),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // The existing edit form, unchanged, behind one row. It stays built
                        // while collapsed so the Form key and the controllers keep working.
                        ExpansionTile(
                          key: _editTileKey,
                          controller: _editTileController,
                          maintainState: true,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          visualDensity: const VisualDensity(vertical: -1),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            20,
                          ),
                          leading: _menuIcon(Icons.person_outline),
                          title: const Text(
                            'Personal information',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: carShareText,
                            ),
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
                                    : (value) => setState(() => _role = value),
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
                        // Vehicles belong to drivers only; a passenger never sees this row.
                        if (user.role.toLowerCase() == 'driver') ...[
                          _menuRow(
                            icon: Icons.directions_car_outlined,
                            title: 'My vehicles',
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
                              builder: (_) => const EmergencyContactsPage(),
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SupportPage(),
                            ),
                          ),
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
                  ),
                  // The pull-up leaves this much empty space at the end of the list.
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far the content under the header is pulled up over it.
  static const _headerOverlap = 50.0;

  /// The mockup draws the rows with no lines between them, only a little air.
  static const _rowDivider = SizedBox(height: 2);

  Widget _menuIcon(IconData icon, {bool danger = false}) => CircleAvatar(
    radius: 18,
    backgroundColor: danger ? carShareDangerTint : carShareTint,
    child: Icon(icon, size: 18, color: danger ? carShareDanger : carShareGreen),
  );

  Widget _menuRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool danger = false,
  }) => ListTile(
    // 52 dp rows with one line of text, as in the mockup.
    visualDensity: const VisualDensity(vertical: -1),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    leading: _menuIcon(icon, danger: danger),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: danger ? carShareDanger : carShareText,
      ),
    ),
    trailing: danger
        ? null
        : const Icon(Icons.chevron_right, color: carShareMuted),
    onTap: onTap,
  );

  String _roleLabel(String role) => switch (role.toLowerCase()) {
    'driver' => 'Driver',
    'admin' => 'Administrator',
    _ => 'Passenger',
  };

  /// Profile summary styled to match the reference screen.
  Widget _buildHeader(UserProfile user) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30 + _headerOverlap),
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(32),
      ),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [carShareSuccess, carShareGreen, carShareGreenDark],
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
                  fontSize: 20,
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
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: _buildAvatar(user.hasProfilePhoto),
        ),
        const SizedBox(height: 12),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.transparent),
          child: Text(
            '${_roleLabel(user.role)} · Member since ${user.createdAt.year}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
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
      elevation: 4,
      shadowColor: const Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(carShareCardRadius),
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

  /// The small round buttons on the avatar's lower corners: 32 dp with a white ring, like the
  /// mockup's verified badge.
  static final _badgeStyle = IconButton.styleFrom(
    minimumSize: const Size(32, 32),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: const BorderSide(color: Colors.white, width: 3),
  );

  Widget _buildAvatar(bool hasPhoto) => Stack(
    clipBehavior: Clip.none,
    children: [
      CircleAvatar(
        radius: 46,
        backgroundColor: carShareWarningTint,
        child: _photoFuture == null
            ? const Icon(
                Icons.person_rounded,
                color: Color(0xFFD97706),
                size: 54,
              )
            : FutureBuilder<Uint8List>(
                future: _photoFuture,
                builder: (context, snapshot) => snapshot.hasData
                    ? ClipOval(
                        child: Image.memory(
                          snapshot.data!,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: Color(0xFFD97706),
                        size: 54,
                      ),
              ),
      ),
      Positioned(
        right: -2,
        bottom: -2,
        child: IconButton.filled(
          style: _badgeStyle,
          tooltip: _photoLoading ? 'Uploading photo' : 'Change profile photo',
          onPressed: _photoLoading ? null : _pickPhoto,
          icon: _photoLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.camera_alt_outlined, size: 15),
        ),
      ),
      if (hasPhoto)
        Positioned(
          left: -2,
          bottom: -2,
          child: IconButton.filledTonal(
            style: _badgeStyle,
            tooltip: 'Remove profile photo',
            onPressed: _photoLoading ? null : _removePhoto,
            icon: const Icon(Icons.delete_outline, size: 15),
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
      elevation: 4,
      shadowColor: const Color(0x22000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(carShareCardRadius),
      ),
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
