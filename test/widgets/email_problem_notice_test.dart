import 'package:carshare/services/api_client.dart';
import 'package:carshare/widgets/email_problem_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the three email refusals become an EmailProblem', () {
    const refused = ApiException(
      'Disposable email addresses aren\'t accepted.',
      statusCode: 400,
      code: 'email_disposable',
    );
    expect(EmailProblem.from(refused)?.message, contains('Disposable'));
    expect(EmailProblem.from(refused)?.suggestion, isNull);
    expect(
      EmailProblem.from(
        const ApiException(
          'x',
          code: 'email_undeliverable',
          suggestion: 'a@gmail.com',
        ),
      )?.suggestion,
      'a@gmail.com',
    );
    expect(
      EmailProblem.from(const ApiException('x', code: 'email_in_use')),
      isNull,
    );
    expect(EmailProblem.from(StateError('nope')), isNull);
  });

  testWidgets('"Did you mean …?" hands the suggestion back', (tester) async {
    String? used;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmailProblemNotice(
            problem: const EmailProblem(
              'We couldn\'t find a mailbox for this address.',
              suggestion: 'test@gmail.com',
            ),
            onUseSuggestion: (address) => used = address,
          ),
        ),
      ),
    );

    expect(find.textContaining('couldn\'t find a mailbox'), findsOneWidget);
    await tester.tap(find.text('Did you mean test@gmail.com?'));
    expect(used, 'test@gmail.com');
  });

  testWidgets('without a suggestion there is no button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmailProblemNotice(
            problem: const EmailProblem(
              'That email address doesn\'t look valid.',
            ),
            onUseSuggestion: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(TextButton), findsNothing);
  });
}
