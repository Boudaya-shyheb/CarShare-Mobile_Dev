import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'photo_category_mapper.dart';

/// Labels a photo on the phone with ML Kit and maps the labels to a report category. The model is
/// bundled with the app: nothing is sent anywhere, and it works offline.
class PhotoLabelingService {
  PhotoLabelingService._();
  static final instance = PhotoLabelingService._();

  /// The suggestion for the image at [filePath], or null when nothing fits or labelling failed.
  /// Labelling is a convenience: any failure just means no chip, never an error for the user.
  Future<PhotoCategorySuggestion?> suggest(String filePath) async {
    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.4),
    );
    try {
      final labels = await labeler.processImage(
        InputImage.fromFilePath(filePath),
      );
      return suggestCategory(
        labels.map((label) => PhotoLabel(label.label, label.confidence)),
      );
    } catch (_) {
      return null;
    } finally {
      await labeler.close();
    }
  }
}
