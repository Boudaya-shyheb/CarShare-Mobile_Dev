import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

const int supportMaxEvidenceBytes = 5 * 1024 * 1024;

bool isSupportEvidenceSizeAllowed(int bytes) =>
    bytes > 0 && bytes <= supportMaxEvidenceBytes;

Future<SupportEvidence?> pickSupportPhoto(BuildContext context) async {
  try {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    if (!context.mounted) return null;
    if (!isSupportEvidenceSizeAllowed(bytes.length)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a non-empty photo no larger than 5 MB.'),
        ),
      );
      return null;
    }
    return SupportEvidence(name: photo.name, isImage: true, bytes: bytes);
  } on PlatformException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message == null || error.message!.isEmpty
                ? 'Could not open the photo gallery.'
                : 'Could not select the photo: ${error.message}',
          ),
        ),
      );
    }
  } on FileSystemException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected photo could not be read.')),
      );
    }
  }
  return null;
}

Future<SupportEvidence?> pickSupportDocument(BuildContext context) async {
  const channel = MethodChannel('carshare.support/document_picker');
  try {
    final file = await channel.invokeMapMethod<String, String>('pickDocument');
    if (file == null || !context.mounted) return null;
    final name = file['name'];
    final uri = file['uri'];
    if (name == null || uri == null || !name.toLowerCase().endsWith('.pdf')) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Choose a PDF document.')));
      }
      return null;
    }
    final bytes = await channel.invokeMethod<Uint8List>('readDocument', {
      'uri': uri,
    });
    if (bytes == null || !isSupportEvidenceSizeAllowed(bytes.length)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a PDF no larger than 5 MB.')),
        );
      }
      return null;
    }
    return SupportEvidence(name: name, isImage: false, bytes: bytes, uri: uri);
  } on PlatformException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not select the PDF document.'),
        ),
      );
    }
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The PDF picker is unavailable in this app build.'),
        ),
      );
    }
  }
  return null;
}

class SupportEvidence {
  const SupportEvidence({
    required this.name,
    required this.isImage,
    this.bytes,
    this.uri,
  });

  final String name;
  final bool isImage;
  final Uint8List? bytes;
  final String? uri;
}

class SupportEvidenceController {
  SupportEvidenceController({List<SupportEvidence> initialEvidence = const []})
    : evidence = ValueNotifier(List.unmodifiable(initialEvidence));

  final ValueNotifier<List<SupportEvidence>> evidence;

  Future<void> showPickerOptions(BuildContext context) async {
    final selection = await showModalBottomSheet<_EvidenceType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Add photo'),
              onTap: () => Navigator.pop(context, _EvidenceType.photo),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('Add document'),
              onTap: () => Navigator.pop(context, _EvidenceType.document),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || selection == null) return;
    await _pick(selection, context);
  }

  Future<void> pickPhoto(BuildContext context) =>
      _pick(_EvidenceType.photo, context);

  Future<void> pickDocuments(BuildContext context) =>
      _pick(_EvidenceType.document, context);

  void remove(int index) {
    final updated = [...evidence.value]..removeAt(index);
    evidence.value = List.unmodifiable(updated);
  }

  Future<void> _pick(_EvidenceType type, BuildContext context) async {
    if (type == _EvidenceType.photo) {
      final photo = await pickSupportPhoto(context);
      if (photo == null) return;
      evidence.value = [...evidence.value, photo];
      return;
    }

    final document = await pickSupportDocument(context);
    if (document != null) evidence.value = [...evidence.value, document];
  }

  void dispose() => evidence.dispose();
}

class SupportEvidenceSection extends StatelessWidget {
  const SupportEvidenceSection({super.key, required this.controller});

  final SupportEvidenceController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ValueListenableBuilder<List<SupportEvidence>>(
        valueListenable: controller.evidence,
        builder: (context, evidence, _) => Text(
          'Evidence (${evidence.length})',
          style: const TextStyle(
            color: carShareText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: () => controller.pickPhoto(context),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add photo'),
          ),
          TextButton.icon(
            onPressed: () => controller.pickDocuments(context),
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: const Text('Add document'),
          ),
        ],
      ),
      ValueListenableBuilder<List<SupportEvidence>>(
        valueListenable: controller.evidence,
        builder: (context, evidence, _) => evidence.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No evidence added yet.',
                  style: TextStyle(color: carShareMuted, fontSize: 12),
                ),
              )
            : Column(
                children: [
                  for (var index = 0; index < evidence.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EvidenceTile(
                        evidence: evidence[index],
                        onRemove: () => controller.remove(index),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

enum _EvidenceType { photo, document }

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence, required this.onRemove});

  final SupportEvidence evidence;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [carShareCardShadow],
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 44,
            height: 44,
            child: evidence.bytes != null
                ? Image.memory(evidence.bytes!, fit: BoxFit.cover)
                : ColoredBox(
                    color: carShareTint,
                    child: Icon(
                      evidence.isImage
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                      color: supportDarkGreen,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            evidence.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: carShareText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove evidence',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 19),
          color: carShareMuted,
        ),
      ],
    ),
  );
}
