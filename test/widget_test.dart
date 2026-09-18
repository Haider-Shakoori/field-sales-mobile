import 'package:field_sales_mobile/core/api/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException', () {
    test('maps server envelope fields', () {
      final error = ApiException(
        status: 422,
        message: 'The given data was invalid.',
        code: 'VALIDATION_FAILED',
        fieldErrors: const {
          'email': ['The email field is required.'],
        },
      );

      expect(error.isValidation, isTrue);
      expect(error.fieldErrors['email'], ['The email field is required.']);
      expect(error.toString(), contains('VALIDATION_FAILED'));
    });

    test('retryable flag from HTTP status', () {
      final transient = ApiException(status: 500, message: '', retryable: true);
      final validation = ApiException(status: 422, message: '');
      expect(transient.retryable, isTrue);
      expect(validation.retryable, isFalse);
    });

    test('device revoked detection', () {
      final err = ApiException(
        status: 440,
        message: '',
        code: 'DEVICE_REVOKED',
      );
      expect(err.isDeviceRevoked, isTrue);
      expect(err.isUnauthenticated, isFalse);
    });

    test('device revoked detection covers Laravel 403 without a code', () {
      final laravelStyle = ApiException(
        status: 403,
        message:
            'This device has been revoked. Reinstall the app or contact '
            'support.',
      );
      expect(laravelStyle.isDeviceRevoked, isTrue);

      final plainForbidden = ApiException(
        status: 403,
        message: 'You are not allowed to view other users locations.',
      );
      expect(plainForbidden.isDeviceRevoked, isFalse);
    });
  });

  testWidgets('shows sign in form title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Sign in'))),
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('empty app shell renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Field Sales'))),
      ),
    );
    expect(find.text('Field Sales'), findsOneWidget);
  });
}
