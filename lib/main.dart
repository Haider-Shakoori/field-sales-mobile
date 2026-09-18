import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/api/attendance_api.dart';
import 'core/api/auth_repository.dart';
import 'core/api/gps_api.dart';
import 'core/location/location_permission_service.dart';
import 'core/location/location_source.dart';
import 'core/permissions/notification_permission_service.dart';
import 'core/storage/attendance_tracking_settings_repository.dart';
import 'core/storage/gps_point_repository.dart';
import 'core/storage/master_data_repository.dart';
import 'core/storage/privacy_ack_store.dart';
import 'core/storage/secret_store.dart';
import 'core/storage/secure_storage.dart';
import 'core/storage/session_meta_store.dart';
import 'core/storage/work_session_repository.dart';
import 'core/sync/connectivity_service.dart';
import 'core/sync/sync_controller.dart';
import 'core/sync/sync_engine.dart';
import 'features/attendance/attendance_controller.dart';
import 'features/attendance/attendance_sync_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/tracking/device_telemetry.dart';
import 'features/tracking/gps_tracking_config.dart';
import 'features/tracking/gps_tracking_service.dart';
import 'features/tracking/gps_upload_service.dart';
import 'l10n/app_l10n.dart';
import 'state/app_state.dart';
import 'state/master_data_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FieldSalesApp());
}

class FieldSalesApp extends StatelessWidget {
  const FieldSalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SecretStore>(create: (_) => SecureStorage()),
        Provider<ApiClient>(
          create: (context) =>
              ApiClient(secureStorage: context.read<SecretStore>()),
        ),
        Provider<AuthRepository>(
          create: (context) => AuthRepository(
            apiClient: context.read<ApiClient>(),
            secureStorage: context.read<SecretStore>(),
          ),
        ),
        Provider<ConnectivityService>(create: (_) => ConnectivityService()),
        Provider<SyncEngine>(
          // Batch 12: no runtime push until POST /api/v1/sync/push exists.
          create: (_) => SyncEngine.deferred(),
        ),
        ChangeNotifierProvider<SyncController>(
          create: (context) => SyncController(
            connectivity: context.read<ConnectivityService>(),
            engine: context.read<SyncEngine>(),
          )..start(),
        ),
        Provider<SessionMetaStore>(create: (_) => SessionMetaStore()),
        Provider<MasterDataRepository>(
          create: (context) =>
              MasterDataRepository(apiClient: context.read<ApiClient>()),
        ),
        ChangeNotifierProvider<MasterDataController>(
          create: (context) =>
              MasterDataController(context.read<MasterDataRepository>()),
        ),

        // Batch 7 — attendance & GPS tracking foundation.
        Provider<AttendanceApi>(
          create: (context) =>
              AttendanceApi(apiClient: context.read<ApiClient>()),
        ),
        Provider<GpsApi>(
          create: (context) => GpsApi(apiClient: context.read<ApiClient>()),
        ),
        Provider<LocationSource>(
          create: (_) => const GeolocatorLocationSource(),
        ),
        Provider<LocationPermissionService>(
          create: (_) => GeolocatorPermissionService(),
        ),
        Provider<NotificationPermissionService>(
          create: (_) => MethodChannelNotificationPermissionService(),
        ),
        Provider<DeviceTelemetryProvider>(
          create: (context) => PlatformDeviceTelemetryProvider(
            connectivity: context.read<ConnectivityService>(),
          ),
        ),
        ChangeNotifierProvider<GpsTrackingService>(
          create: (context) => GpsTrackingService(
            locationSource: context.read<LocationSource>(),
            workSessions: WorkSessionRepository.instance,
            gpsPoints: GpsPointRepository.instance,
            telemetry: context.read<DeviceTelemetryProvider>(),
            config: const GpsTrackingConfig(),
          ),
        ),
        Provider<GpsUploadService>(
          create: (context) => GpsUploadService(
            gpsPoints: GpsPointRepository.instance,
            gpsApi: context.read<GpsApi>(),
            connectivity: context.read<ConnectivityService>(),
          ),
        ),
        Provider<AttendanceSyncService>(
          create: (context) =>
              AttendanceSyncService(api: context.read<AttendanceApi>()),
        ),
        Provider<AttendanceTrackingSettingsRepository>(
          create: (_) => AttendanceTrackingSettingsRepository.instance,
        ),
        ChangeNotifierProvider<AttendanceController>(
          create: (context) => AttendanceController(
            workSessions: WorkSessionRepository.instance,
            privacyAcks: PrivacyAckStore.instance,
            permissions: context.read<LocationPermissionService>(),
            locationSource: context.read<LocationSource>(),
            tracking: context.read<GpsTrackingService>(),
            gpsUpload: context.read<GpsUploadService>(),
            attendanceSync: context.read<AttendanceSyncService>(),
            connectivity: context.read<ConnectivityService>(),
            secureStorage: context.read<SecretStore>(),
            notificationPermissions: context
                .read<NotificationPermissionService>(),
            settingsRepository: context
                .read<AttendanceTrackingSettingsRepository>(),
          )..restore(),
        ),
        ChangeNotifierProvider<AppState>(
          create: (context) => AppState(
            auth: context.read<AuthRepository>(),
            sync: context.read<SyncController>(),
            secureStorage: context.read<SecretStore>(),
            sessionMeta: context.read<SessionMetaStore>(),
            attendance: context.read<AttendanceController>(),
          )..restore(),
        ),
      ],
      child: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      title: 'Field Sales',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('en'),
      supportedLocales: AppL10n.supported,
      home: appState.restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : appState.isSignedIn
          ? const HomeShell()
          : const LoginScreen(),
    );
  }
}
