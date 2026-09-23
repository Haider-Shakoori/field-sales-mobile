import 'dart:convert';
import 'dart:io';

import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/db/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/features/financial_documents/customer_statement_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _databasePath() async =>
    p.join(await getDatabasesPath(), 'field_sales.db');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await deleteDatabase(await _databasePath());
  });

  test('database v14 creates tenant-safe statement cache', () async {
    final db = AppDatabase();
    await db.open();

    final tables = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();
    final indexes = (await db.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    )).map((row) => row['name']).toSet();

    expect(tables, contains('local_customer_statements'));
    expect(
      indexes,
      containsAll(['idx_statement_range', 'idx_statement_customer']),
    );

    await db.db.close();
  });

  test(
    'cached customer statement is available without network refresh',
    () async {
      final db = AppDatabase();
      await db.open();

      const tenantId = 'statement-tenant';
      const customerId = 'customer-1';
      const payload = {
        'customer': {
          'id': customerId,
          'code': 'CUS-001',
          'name': 'Customer One',
        },
        'from': '2026-09-01',
        'to': '2026-09-30',
        'timezone': 'Asia/Kabul',
        'currency': 'AFN',
        'opening_balance': 800.0,
        'debits': 500.0,
        'credits': 300.0,
        'closing_balance': 1000.0,
        'entries': [
          {
            'type': 'invoice',
            'occurred_at': '2026-09-10T08:00:00.000000Z',
            'reference': 'ORD-001',
            'description': 'Credit sale',
            'debit': 500.0,
            'credit': 0.0,
            'balance': 1300.0,
          },
          {
            'type': 'collection',
            'occurred_at': '2026-09-15T08:00:00.000000Z',
            'reference': 'REC-001',
            'description': 'Payment received',
            'debit': 0.0,
            'credit': 300.0,
            'balance': 1000.0,
          },
        ],
      };

      await db.db.insert('local_customer_statements', {
        'tenant_id': tenantId,
        'customer_uuid': customerId,
        'currency': 'AFN',
        'from_date': '2026-09-01',
        'to_date': '2026-09-30',
        'payload': jsonEncode(payload),
        'cached_at': DateTime.utc(2026, 9, 23).toIso8601String(),
      });

      final repository = CustomerStatementRepository(
        api: ApiClient(SecretStore()),
        db: db,
      );

      final statement = await repository.load(
        tenantId: tenantId,
        customerUuid: customerId,
        from: '2026-09-01',
        to: '2026-09-30',
        currency: 'AFN',
        refresh: false,
      );

      expect(statement['_cached'], true);
      expect(statement['opening_balance'], 800.0);
      expect(statement['closing_balance'], 1000.0);
      expect((statement['entries'] as List), hasLength(2));

      await db.db.close();
    },
  );

  test('mobile invoice entry point is approved-order only', () {
    final detail = File('lib/ui/order_detail_screen.dart').readAsStringSync();
    final invoice = File('lib/ui/invoice_screen.dart').readAsStringSync();

    expect(detail, contains("if (order['status'] == 'approved')"));
    expect(invoice, contains("if (order['status'] != 'approved')"));
  });
}
