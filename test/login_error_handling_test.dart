import 'dart:io';

import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:field_sales_mobile/ui/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login exposes optional company tenant field and sends it to API', () {
    final login = File('lib/ui/login_screen.dart').readAsStringSync();
    final auth = File('lib/features/auth/auth_repository.dart')
        .readAsStringSync();

    expect(login, contains('Company / Tenant code'));
    expect(login, contains('Optional unless your email is used'));
    expect(auth, contains("'tenant': tenant!.trim()"));
  });

  test('tenant ambiguity is explained without exposing raw API errors', () {
    final message = friendlyLoginError(
      ApiException(
        status: 422,
        code: 'TENANT_REQUIRED',
        message: 'This email belongs to more than one company.',
      ),
    );

    expect(message, contains('more than one company'));
    expect(message, contains('Company / Tenant code'));
  });

  test('server failures have a recoverable user-facing login message', () {
    final message = friendlyLoginError(
      ApiException(
        status: 500,
        code: 'SERVER_ERROR',
        message: 'Server error.',
        retryable: true,
      ),
    );

    expect(message, contains('server could not complete'));
    expect(message, isNot(contains('Exception')));
  });

  test('mobile role error explicitly includes supervisor access', () {
    final message = friendlyLoginError(
      ApiException(
        status: 422,
        code: 'MOBILE_ROLE_REQUIRED',
        message: 'Role not enabled.',
      ),
    );

    expect(message, contains('Supervisor'));
    expect(message, contains('Sales Manager'));
  });
}
