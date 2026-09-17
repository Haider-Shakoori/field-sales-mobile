import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/models/session.dart';
import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared test harness: an in-memory SQLite DB backed by sqflite_common_ffi
/// and an in-memory secret store, so DATABASE/OFFLINE/AUTH/MAPPING/OUTBOX
/// tests never touch platform plugins or the network.
///
/// Call [initTestDatabase] in each `setUp` to get a BRAND-NEW database
/// (opening `inMemoryDatabasePath` again yields a fresh DB, so tests stay
/// isolated).
Future<void> initTestDatabase() async {
  sqfliteFfiInit();
  await AppDatabase.close();
  final opened = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.version,
      onCreate: AppDatabase.createSchema,
      onUpgrade: AppDatabase.upgradeSchema,
    ),
  );
  AppDatabase.overrideInstance(opened);
}

Future<void> tearDownDatabase() => AppDatabase.close();

/// Minimal in-memory [SecretStore] for auth tests.
class FakeSecretStore implements SecretStore {
  FakeSecretStore({this.installationUuid = ''});

  String? token;
  String installationUuid;
  String? cachedEmail;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<String> readInstallationUuid() async => installationUuid;

  @override
  Future<void> writeInstallationUuid(String value) async =>
      installationUuid = value;

  @override
  Future<String?> readCachedEmail() async => cachedEmail;

  @override
  Future<void> writeCachedEmail(String value) async => cachedEmail = value;
}

/// Builds a server-shaped envelope map for a request.
Map<String, dynamic> envelope({dynamic data, Map<String, dynamic>? meta}) => {
  'success': true,
  'data': data,
  'meta': meta ?? <String, dynamic>{},
  'error': null,
};

/// A fake API client usable with `requestEnvelope` based reads.
class FakeApiClient extends ApiClient {
  FakeApiClient({SecretStore? store, this.onEnvelope})
    : super(secureStorage: store ?? FakeSecretStore());

  /// Returns a canned envelope per path; throws [ApiClientFakeUnconfigured]
  /// if [onEnvelope] is null.
  final Future<ApiEnvelope> Function(String path, Map<String, dynamic>? query)?
  onEnvelope;

  @override
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final handler = onEnvelope;
    if (handler != null) {
      return handler(path, query);
    }
    throw ApiClientFakeUnconfigured(path);
  }
}

/// Marks tests that lacked a route handler.
class ApiClientFakeUnconfigured implements Exception {
  const ApiClientFakeUnconfigured(this.path);

  final String path;

  @override
  String toString() => 'ApiClientFakeUnconfigured: $path';
}

/// A sample authenticated session, shaped like the login response.
Session sampleSession() => Session(
  token: 'tok-123',
  user: UserInfo(
    id: 7,
    name: 'Salesman Seven',
    email: 'sales@shop.test',
    role: 'salesman',
  ),
  tenant: TenantInfo(id: 3, name: 'Shop Three'),
  permissions: const ['customers:read', 'products:read'],
);

/// Database-level assertion helper.
class DbAsserts {
  static Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final db = await AppDatabase.instance;
    return db.rawQuery(sql, args);
  }
}
