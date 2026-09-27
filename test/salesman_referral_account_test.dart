import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('salesman account exposes referral portfolio metrics', () {
    final repository = File('lib/features/team/team_repository.dart')
        .readAsStringSync();
    final more = File('lib/ui/more_screen.dart').readAsStringSync();
    final account = File('lib/ui/salesman_account_screen.dart')
        .readAsStringSync();

    expect(repository, contains("'referrals/me'"));
    expect(more, contains("'My Account'"));
    expect(more, contains('SalesmanAccountScreen'));
    expect(account, contains("'Referred customers'"));
    expect(account, contains("'Orders'"));
    expect(account, contains("'Collections'"));
    expect(account, contains("'Visits'"));
    expect(account, contains("'Outstanding'"));
    expect(account, contains("'Assigned to me'"));
  });
}
