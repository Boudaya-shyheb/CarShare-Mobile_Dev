import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../services/user_management_service.dart';
import '../widgets/form_field.dart';
import '../widgets/primary_button.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  final _home = TextEditingController();
  final _work = TextEditingController();
  final _campus = TextEditingController();
  String _language = 'en';
  String _luggage = 'standard';
  bool _music = true;
  bool _smoking = false;
  bool _pets = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _home.dispose();
    _work.dispose();
    _campus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preferences = await UserManagementService.instance.getPreferences();
      if (!mounted) return;
      setState(() {
        _language = preferences.language;
        _home.text = preferences.homePlace ?? '';
        _work.text = preferences.workPlace ?? '';
        _campus.text = preferences.campusPlace ?? '';
        _music = preferences.musicAllowed;
        _smoking = preferences.smokingAllowed;
        _pets = preferences.petsAllowed;
        _luggage = preferences.luggagePreference;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserManagementService.instance.updatePreferences(
        UserPreferences(
          language: _language,
          homePlace: _home.text.trim().isEmpty ? null : _home.text.trim(),
          workPlace: _work.text.trim().isEmpty ? null : _work.text.trim(),
          campusPlace: _campus.text.trim().isEmpty ? null : _campus.text.trim(),
          musicAllowed: _music,
          smokingAllowed: _smoking,
          petsAllowed: _pets,
          luggagePreference: _luggage,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Preferences saved.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preferences')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Saved places',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    CarShareTextField(
                      controller: _home,
                      label: 'Home',
                      icon: Icons.home_outlined,
                    ),
                    const SizedBox(height: 12),
                    CarShareTextField(
                      controller: _work,
                      label: 'Work',
                      icon: Icons.work_outline,
                    ),
                    const SizedBox(height: 12),
                    CarShareTextField(
                      controller: _campus,
                      label: 'Campus',
                      icon: Icons.school_outlined,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Ride preferences',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      title: const Text('Music is okay'),
                      value: _music,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _music = value),
                    ),
                    SwitchListTile(
                      title: const Text('Smoking is okay'),
                      value: _smoking,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _smoking = value),
                    ),
                    SwitchListTile(
                      title: const Text('Pets are okay'),
                      value: _pets,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _pets = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _luggage,
                      decoration: const InputDecoration(
                        labelText: 'Luggage preference',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('Standard'),
                        ),
                        DropdownMenuItem(
                          value: 'small',
                          child: Text('Small luggage'),
                        ),
                        DropdownMenuItem(
                          value: 'large',
                          child: Text('Large luggage'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _luggage = value ?? 'standard'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Save preferences',
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
