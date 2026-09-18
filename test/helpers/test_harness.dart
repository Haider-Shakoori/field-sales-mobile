import 'dart:async';

import 'package:field_sales_mobile/core/api/api_client.dart';
import 'package:field_sales_mobile/core/location/location_fix.dart';
import 'package:field_sales_mobile/core/location/location_permission_service.dart';
import 'package:field_sales_mobile/core/location/location_source.dart';
import 'package:field_sales_mobile/core/models/session.dart';
import 'package:field_sales_mobile/core/permissions/notification_permission_service.dart';
import 'package:field_sales_mobile/core/storage/app_database.dart';
import 'package:field_sales_mobile/core/storage/secret_store.dart';
import 'package:field_sales_mobile/core/sync/connectivity_service.dart';
import 'package:field_sales_mobile/core/time/clock.dart';
import 'package:field_sales_mobile/features/attendance/boundary_scheduler.dart';
import 'package:field_sales_mobile/features/tracking/device_telemetry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared test harness: an in-memory SQLite DB backed by sqflite_common_ffi
/// and an in-memory secret store, so DATABASE/OFFLINE/AUTH/MAPPING/OUTBOX
/// tests never touch platform plugins or the network.
///
/// Call [initTestDatabase] in each `setUp` to get a BRAND-NEW database
/// (opening `inMemoryDatabasePath` again yields a fresh DB, so tests stay
/// isolated).
///
/// Widget tests must pass `noIsolate: true`: the default isolate-backed
/// factory completes on the real event loop, which the widget test FakeAsync
/// zone never drains.
Future<void> initTestDatabase({bool noIsolate = false}) async {
  sqfliteFfiInit();
  await AppDatabase.close();
  final factory = noIsolate ? databaseFactoryFfiNoIsolate : databaseFactoryFfi;
  final opened = await factory.openDatabase(
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

/// Configurable fake location source for tracking tests.
class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.serviceEnabled = true, LocationFix? current})
    : current =
          current ??
          LocationFix(
            latitude: 34.5553,
            longitude: 69.2075,
            accuracy: 8,
            speed: 0,
            recordedAt: DateTime.utc(2026, 1, 15, 8),
          );

  bool serviceEnabled;
  LocationFix? current;

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();
  final List<({Duration interval, bool foregroundNotification})> subscriptions =
      [];

  /// Emits a fix to every active subscription.
  void emit(LocationFix fix) => _controller.add(fix);

  void emitError(Object error) => _controller.addError(error);

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 20),
    LocationAccuracyPreset accuracy = LocationAccuracyPreset.high,
  }) async => current;

  @override
  Stream<LocationFix> fixes({
    required Duration interval,
    bool foregroundNotification = true,
  }) {
    subscriptions.add((
      interval: interval,
      foregroundNotification: foregroundNotification,
    ));
    return _controller.stream;
  }

  Future<void> close() => _controller.close();
}

/// Configurable fake permission service covering every flow branch.
class FakeLocationPermissionService implements LocationPermissionService {
  FakeLocationPermissionService({
    this.serviceEnabled = true,
    this.foreground = LocationPermissionStatus.whileInUse,
    this.background = BackgroundLocationAccess.denied,
    this.requestForegroundResult,
    this.backgroundRequestResult,
  });

  bool serviceEnabled;
  LocationPermissionStatus foreground;
  BackgroundLocationAccess background;
  LocationPermissionStatus? requestForegroundResult;
  BackgroundLocationAccess? backgroundRequestResult;

  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;
  int requestForegroundCalls = 0;
  int requestBackgroundCalls = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkForeground() async => foreground;

  @override
  Future<LocationPermissionStatus> requestForeground() async {
    requestForegroundCalls++;
    final result = requestForegroundResult ?? foreground;
    foreground = result;
    return result;
  }

  @override
  Future<BackgroundLocationAccess> checkBackground() async => background;

  @override
  Future<BackgroundLocationAccess> requestBackground() async {
    requestBackgroundCalls++;
    final result = backgroundRequestResult ?? background;
    background = result;
    return result;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    return true;
  }
}

/// Fake notification permission service (defaults to granted).
class FakeNotificationPermissionService
    implements NotificationPermissionService {
  FakeNotificationPermissionService({this.granted = true});

  bool granted;
  int requestCalls = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requestCalls++;
    return granted;
  }
}

/// Deterministic telemetry for GPS point tests.
class FakeDeviceTelemetryProvider implements DeviceTelemetryProvider {
  FakeDeviceTelemetryProvider({
    this.batteryLevel = 80,
    this.isCharging = false,
    this.networkStatus = 'wifi',
  });

  int? batteryLevel;
  bool isCharging;
  String? networkStatus;

  @override
  Future<DeviceTelemetry> read() async => DeviceTelemetry(
    batteryLevel: batteryLevel,
    isCharging: isCharging,
    networkStatus: networkStatus,
  );
}

/// Connectivity stand-in with a directly controllable online flag.
class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService({this.online = true});

  bool online;

  @override
  bool get isOnline => online;

  @override
  String get connectionType => online ? 'wifi' : 'offline';
}

/// Records the requests a fake API client receives (method/path/body/key).
class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.path,
    this.query,
    this.body,
    this.idempotencyKey,
  });

  final String method;
  final String path;
  final Map<String, dynamic>? query;
  final Object? body;
  final String? idempotencyKey;
}

/// API client that answers per path and records every request.
class RecordingApiClient extends ApiClient {
  RecordingApiClient({required this.handler, SecretStore? store})
    : super(secureStorage: store ?? FakeSecretStore());

  final Future<ApiEnvelope> Function(RecordedRequest request) handler;
  final List<RecordedRequest> requests = [];

  @override
  Future<ApiEnvelope> requestEnvelope({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final request = RecordedRequest(
      method: method,
      path: path,
      query: query,
      body: body,
      idempotencyKey: idempotencyKey,
    );
    requests.add(request);
    return handler(request);
  }
}

/// Waits until [condition] is true or [timeout] elapses (polling ~10ms).
///
/// GPS stream processing crosses an async isolate boundary in tests, so
/// asserting immediately after `emit` is racy; this makes those tests
/// deterministic.
Future<void> waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Mutable clock for deterministic policy tests.
class TestClock extends Clock {
  TestClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);
}

/// Boundary scheduler stand-in that records delays and can be fired manually.
class FakeBoundaryScheduler implements BoundaryScheduler {
  final List<Duration> scheduledDelays = [];
  void Function()? _callback;

  bool get isScheduled => _callback != null;

  @override
  void schedule(Duration delay, void Function() callback) {
    scheduledDelays.add(delay);
    _callback = callback;
  }

  @override
  void cancel() {
    _callback = null;
  }

  /// Simulates the boundary timer firing.
  void fire() {
    final callback = _callback;
    _callback = null;
    callback?.call();
  }
}
