import 'package:flutter/material.dart';

import '../services/user_management_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/form_field.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  late Future<List<Map<String, dynamic>>> _contacts = UserManagementService
      .instance
      .getEmergencyContacts();
  bool _saving = false;

  void _refresh() => setState(() {
    _contacts = UserManagementService.instance.getEmergencyContacts();
  });

  Future<void> _edit([Map<String, dynamic>? contact]) async {
    final draft = await showDialog<_EmergencyContactDraft>(
      context: context,
      builder: (_) => _EmergencyContactDialog(contact: contact),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await UserManagementService.instance.saveEmergencyContact(
        id: contact?['id'] as String?,
        name: draft.name,
        phone: draft.phone,
        relationship: draft.relationship,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await UserManagementService.instance.deleteEmergencyContact(id);
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Emergency contacts')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add contact'),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _contacts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final contacts = snapshot.data ?? const <Map<String, dynamic>>[];
        if (contacts.isEmpty) {
          return const EmptyState(
            icon: Icons.contact_phone_outlined,
            title: 'No emergency contacts yet',
            line: 'Add someone we can reach if something goes wrong on a ride.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: contacts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.contact_phone_outlined),
                ),
                title: Text(contact['name'] as String),
                subtitle: Text(
                  '${contact['relationship']} · ${contact['phone']}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => value == 'edit'
                      ? _edit(contact)
                      : _delete(contact['id'] as String),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _EmergencyContactDraft {
  const _EmergencyContactDraft({
    required this.name,
    required this.phone,
    required this.relationship,
  });

  final String name;
  final String phone;
  final String relationship;
}

class _EmergencyContactDialog extends StatefulWidget {
  const _EmergencyContactDialog({this.contact});

  final Map<String, dynamic>? contact;

  @override
  State<_EmergencyContactDialog> createState() =>
      _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<_EmergencyContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.contact?['name'] as String? ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.contact?['phone'] as String? ?? '',
  );
  late final TextEditingController _relationship = TextEditingController(
    text: widget.contact?['relationship'] as String? ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relationship.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // Keep the form usable on short screens and while the keyboard is open.
    scrollable: true,
    title: Text(
      widget.contact == null
          ? 'Add emergency contact'
          : 'Edit emergency contact',
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CarShareTextField(
            controller: _name,
            label: 'Full name',
            icon: Icons.person_outline,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Name is required.'
                : null,
          ),
          const SizedBox(height: 12),
          CarShareTextField(
            controller: _phone,
            label: 'Phone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (value) =>
                value == null || value.replaceAll(RegExp(r'\D'), '').length < 7
                ? 'Enter a valid phone number.'
                : null,
          ),
          const SizedBox(height: 12),
          CarShareTextField(
            controller: _relationship,
            label: 'Relationship',
            icon: Icons.people_outline,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Relationship is required.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _EmergencyContactDraft(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              relationship: _relationship.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
