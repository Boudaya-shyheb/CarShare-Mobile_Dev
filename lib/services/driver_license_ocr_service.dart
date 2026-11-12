import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DriverLicenseOcrService {
  Future<List<DateTime>> readPossibleExpiryDates(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final lines = text.text.split(RegExp(r'[\r\n]+'));
      final expiryLines = lines.where(
        (line) => RegExp(
          r'expir|valid\s*(until|to)|date\s*of\s*expiry',
          caseSensitive: false,
        ).hasMatch(line),
      );
      final candidates = _dates(expiryLines.join(' '));
      return candidates.isNotEmpty ? candidates : _dates(text.text);
    } finally {
      await recognizer.close();
    }
  }

  List<DateTime> _dates(String text) {
    final values = <DateTime>{};
    final patterns = [
      RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2})\b'),
      RegExp(r'\b(20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b'),
    ];
    for (final match in patterns[0].allMatches(text)) {
      final day = int.parse(match[1]!);
      final month = int.parse(match[2]!);
      final year = int.parse(match[3]!);
      _addValid(values, year, month, day);
    }
    for (final match in patterns[1].allMatches(text)) {
      final year = int.parse(match[1]!);
      final month = int.parse(match[2]!);
      final day = int.parse(match[3]!);
      _addValid(values, year, month, day);
    }
    return values.toList()..sort();
  }

  void _addValid(Set<DateTime> dates, int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return;
    final date = DateTime(year, month, day);
    if (date.year == year && date.month == month && date.day == day) {
      dates.add(date);
    }
  }
}
