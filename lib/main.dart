import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/api/auth_repository.dart';
import 'core/storage/master_data_repository.dart';
import 'core/storage/secret_store.dart';
import 'core/storage/secure_storage.dart';
import 'core/storage/session_meta_store.dart';
import 'core/sync/connectivity_service.dart';
import 'core/sync/sync_controller.dart';
import 'core/sync/sync_engine.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
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
        ChangeNotifierProvider<AppState>(
          create: (context) => AppState(
            auth: context.read<AuthRepository>(),
            sync: context.read<SyncController>(),
            secureStorage: context.read<SecretStore>(),
            sessionMeta: context.read<SessionMetaStore>(),
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
