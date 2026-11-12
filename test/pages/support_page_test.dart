import 'package:carshare/pages/support/support_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'refreshing the Support list does not return a future from setState',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SupportPage()));
      await tester.pumpAndSettle();

      expect(find.text('No open tickets'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('No open tickets'), findsOneWidget);
    },
  );
}
