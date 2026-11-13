import 'package:carshare/models/lost_and_found_notification.dart';
import 'package:carshare/services/photo_category_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestCategory', () {
    test('maps a mobile phone label to Phone with its confidence', () {
      final suggestion = suggestCategory(const [
        PhotoLabel('Gadget', 0.95),
        PhotoLabel('Mobile phone', 0.87),
      ]);
      expect(suggestion?.category, 'Phone');
      expect(suggestion?.percent, 87);
    });

    test('maps bags, wallets, keys, glasses and clothing', () {
      expect(
        suggestCategory(const [PhotoLabel('Backpack', 0.8)])?.category,
        'Bag',
      );
      expect(
        suggestCategory(const [PhotoLabel('Wallet', 0.7)])?.category,
        'Wallet',
      );
      expect(
        suggestCategory(const [PhotoLabel('Keychain', 0.7)])?.category,
        'Keys',
      );
      expect(
        suggestCategory(const [PhotoLabel('Sunglasses', 0.9)])?.category,
        'Glasses',
      );
      expect(
        suggestCategory(const [PhotoLabel('Jacket', 0.9)])?.category,
        'Clothing',
      );
    });

    test('picks the most confident matching label', () {
      final suggestion = suggestCategory(const [
        PhotoLabel('Bag', 0.6),
        PhotoLabel('Sunglasses', 0.9),
      ]);
      expect(suggestion?.category, 'Glasses');
    });

    test('ignores weak labels and labels that name no item', () {
      expect(suggestCategory(const [PhotoLabel('Phone', 0.3)]), isNull);
      expect(
        suggestCategory(const [
          PhotoLabel('Room', 0.99),
          PhotoLabel('Floor', 0.9),
        ]),
        isNull,
      );
    });

    test('a word only counts as a whole word', () {
      expect(categoryOfLabel('Keyboard'), isNull);
      expect(categoryOfLabel('Capital'), isNull);
      expect(categoryOfLabel('Car key'), 'Keys');
    });
  });

  test('LostAndFoundNotification reads and writes its JSON', () {
    final notification = LostAndFoundNotification.fromJson({
      'id': 'n1',
      'type': 'MATCH_FOUND',
      'title': 'Match found',
      'body': 'Someone reported a similar item.',
      'read': false,
      'createdAt': '2026-11-13T10:00:00Z',
      'reportId': 'r1',
      'handoverId': null,
    });
    expect(notification.read, isFalse);
    expect(notification.reportId, 'r1');
    expect(notification.handoverId, isNull);
    expect(notification.toJson()['createdAt'], '2026-11-13T10:00:00.000Z');
  });
}
