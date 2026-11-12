import 'package:flutter/material.dart';

import '../theme.dart';
import 'form_field.dart';

/// The icon for a favourite place: a house for "Home", a bag for "Work", a cap for
/// "University" or "Campus", and a star for any other name.
IconData favoriteIcon(String name) {
  switch (name.trim().toLowerCase()) {
    case 'home':
      return Icons.home_outlined;
    case 'work':
      return Icons.work_outline;
    case 'university':
    case 'campus':
      return Icons.school_outlined;
    default:
      return Icons.star_border_rounded;
  }
}

/// Asks the user to name a place ("Home", "Work"...). Used to save a new favourite and to
/// rename one. Returns the name, or null if the dialog is cancelled.
///
/// [takenNames] are the names already used, so the form can refuse a duplicate. When renaming,
/// leave the place's own name out of the list.
Future<String?> askFavoriteName(
  BuildContext context, {
  String? initialName,
  Iterable<String> takenNames = const [],
}) => showDialog<String>(
  context: context,
  builder: (_) => _FavoriteNameDialog(
    initialName: initialName,
    takenNames: takenNames.toList(),
  ),
);

class _FavoriteNameDialog extends StatefulWidget {
  const _FavoriteNameDialog({
    required this.initialName,
    required this.takenNames,
  });

  final String? initialName;
  final List<String> takenNames;

  @override
  State<_FavoriteNameDialog> createState() => _FavoriteNameDialogState();
}

class _FavoriteNameDialogState extends State<_FavoriteNameDialog> {
  static const _suggestions = ['Home', 'Work', 'University'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Give this place a name.';
    if (name.length > 30) return 'Keep it under 30 characters.';
    final taken = widget.takenNames.any(
      (other) => other.toLowerCase() == name.toLowerCase(),
    );
    if (taken) return 'You already have a place with this name.';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions.where(
      (name) => !widget.takenNames.any(
        (other) => other.toLowerCase() == name.toLowerCase(),
      ),
    );
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        widget.initialName == null ? 'Name this place' : 'Rename place',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CarShareTextField(
              controller: _name,
              label: 'Name',
              icon: Icons.star_border_rounded,
              validator: _validate,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final name in suggestions)
                  ActionChip(
                    avatar: Icon(
                      favoriteIcon(name),
                      size: 16,
                      color: carShareGreen,
                    ),
                    label: Text(name),
                    onPressed: () => _name.text = name,
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
