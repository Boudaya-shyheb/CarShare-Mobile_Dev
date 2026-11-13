/// Turns the labels ML Kit finds in a photo into one of the report form's categories.
///
/// Kept apart from ML Kit itself so it is plain Dart and easy to read and test. Each category has
/// a short list of words; a label counts for a category when it IS one of the words or contains
/// one as a whole word ("Mobile phone" counts for Phone, "Keyboard" does not count for Keys).
/// The category with the most confident matching label wins.
library;

/// One label as ML Kit reports it.
class PhotoLabel {
  const PhotoLabel(this.text, this.confidence);
  final String text;

  /// 0 to 1.
  final double confidence;
}

/// "Looks like: Phone (87%)".
class PhotoCategorySuggestion {
  const PhotoCategorySuggestion({
    required this.category,
    required this.confidence,
    required this.label,
  });

  /// The form's category name: Phone, Keys, Wallet, Bag, Documents, Glasses or Clothing.
  final String category;
  final double confidence;

  /// The ML Kit label that decided it.
  final String label;

  int get percent => (confidence * 100).round();
}

/// The words that say which category a label belongs to. Anything not here (Gadget, Technology,
/// Room, Floor...) says nothing about the item and is ignored. The form's "Other" is never
/// suggested: if nothing fits, no suggestion is better than a wrong one.
const Map<String, List<String>> photoCategoryWords = {
  'Phone': [
    'mobile phone',
    'phone',
    'smartphone',
    'cell phone',
    'telephone',
    'iphone',
    'communication device',
    'portable communications device',
  ],
  'Bag': [
    'bag',
    'backpack',
    'handbag',
    'luggage',
    'suitcase',
    'briefcase',
    'tote',
    'satchel',
    'purse',
    'duffel',
  ],
  'Wallet': ['wallet', 'coin purse', 'billfold'],
  'Keys': ['key', 'keys', 'keychain', 'key ring'],
  'Glasses': ['glasses', 'sunglasses', 'eyewear', 'spectacles', 'goggles'],
  'Clothing': [
    'clothing',
    'shirt',
    't-shirt',
    'jacket',
    'coat',
    'dress',
    'sweater',
    'hoodie',
    'scarf',
    'hat',
    'cap',
    'glove',
    'jeans',
    'trousers',
    'shoe',
    'sneaker',
    'outerwear',
    'sleeve',
  ],
  'Documents': [
    'document',
    'paper',
    'passport',
    'book',
    'card',
    'notebook',
    'envelope',
    'receipt',
    'identity document',
  ],
};

/// Below this the label is too uncertain to put a name on the item.
const double minimumLabelConfidence = 0.5;

/// The best category for [labels], or null when no label is confident enough or none fits.
PhotoCategorySuggestion? suggestCategory(
  Iterable<PhotoLabel> labels, {
  double minimumConfidence = minimumLabelConfidence,
}) {
  PhotoCategorySuggestion? best;
  for (final label in labels) {
    if (label.confidence < minimumConfidence) continue;
    final category = categoryOfLabel(label.text);
    if (category == null) continue;
    if (best == null || label.confidence > best.confidence) {
      best = PhotoCategorySuggestion(
        category: category,
        confidence: label.confidence,
        label: label.text,
      );
    }
  }
  return best;
}

/// The category a single label belongs to, or null.
String? categoryOfLabel(String text) {
  final label = text.trim().toLowerCase();
  for (final entry in photoCategoryWords.entries) {
    for (final word in entry.value) {
      if (label == word ||
          RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(label)) {
        return entry.key;
      }
    }
  }
  return null;
}
