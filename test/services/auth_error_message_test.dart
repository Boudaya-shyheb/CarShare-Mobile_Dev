import 'package:carshare/services/api_client.dart';
import 'package:carshare/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a suspension names the end date in the phone local time', () {
    final until = DateTime.utc(2026, 11, 14, 10, 30).toLocal();

    final message = authErrorMessage(
      ApiException(
        'server text',
        statusCode: 403,
        code: 'account_suspended',
        statusUntil: until,
      ),
    );

    expect(message, startsWith('Your account is suspended until 14 Nov 2026'));
    expect(message, contains('look around'));
  });

  test('a suspension with no end date keeps the server sentence', () {
    const error = ApiException(
      'Your account is suspended, so you cannot make changes. Contact CarShare support.',
      statusCode: 403,
      code: 'account_suspended',
    );

    expect(authErrorMessage(error), error.message);
  });

  test('a banned account shows the server sentence, which is already friendly', () {
    const error = ApiException(
      'Your account has been banned, so you can no longer use CarShare.',
      statusCode: 403,
      code: 'account_banned',
    );

    expect(authErrorMessage(error), contains('banned'));
  });

  test('deletion refused during a suspension says when it ends', () {
    final message = authErrorMessage(
      ApiException(
        'x',
        statusCode: 409,
        code: 'delete_blocked_suspended',
        statusUntil: DateTime.utc(2026, 11, 14, 10, 30).toLocal(),
      ),
    );

    expect(message, contains('cannot delete your account'));
    expect(message, contains('14 Nov 2026'));
  });

  test('role-change and deletion refusals pass the server sentence through', () {
    const roleChange = ApiException(
      'You cannot switch to a passenger account while you have a trip that has not finished.',
      statusCode: 409,
      code: 'role_change_active_trips',
    );
    const deletion = ApiException(
      'You still have a trip that has not finished.',
      statusCode: 409,
      code: 'delete_blocked_active_trips',
    );

    expect(authErrorMessage(roleChange), roleChange.message);
    expect(authErrorMessage(deletion), deletion.message);
  });

  test('anything that is not an ApiException gets the generic line', () {
    expect(
      authErrorMessage(StateError('boom')),
      'We could not complete your request. Please try again.',
    );
  });
}
