import 'dart:async';

import 'package:field_sales_mobile/l10n/localized_material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/notifications/push_service.dart';
import 'l10n/locale_controller.dart';
import 'state/app_state.dart';
import 'ui/dashboard_screen.dart';
import 'ui/fieldpulse_splash_screen.dart';
import 'ui/fieldpulse_theme.dart';
import 'ui/login_screen.dart';
import 'ui/notifications_screen.dart';
import 'ui/smart_route_screen.dart';
import 'ui/leadership_dashboard_screen.dart';

class FieldSalesApp extends StatefulWidget {
  const FieldSalesApp({super.key});

  @override
  State<FieldSalesApp> createState() => _FieldSalesAppState();
}

class _FieldSalesAppState extends State<FieldSalesApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Map<String, dynamic>>? _pushSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pushSubscription ??= context.read<PushService>().opened.listen(_openPush);
  }

  void _openPush(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null || context.read<AppState>().signedIn == false) return;

    final screen = data['screen']?.toString();
    final Widget destination = switch (screen) {
      'smart_route' => const SmartRouteScreen(),
      'team' => const LeadershipDashboardScreen(),
      _ => const NotificationsScreen(),
    };

    navigator.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              screen == 'smart_route'
                  ? 'Smart Route'
                  : screen == 'team'
                  ? 'Team'
                  : 'Notifications',
            ),
          ),
          body: destination,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Consumer<AppLocaleController>(
    builder: (_, locale, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: 'FieldPulse',
      debugShowCheckedModeBanner: false,
      locale: locale.locale,
      supportedLocales: AppLocaleController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: FieldPulseTheme.light(),
      home: const _StartupGate(),
    ),
  );
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  static const _brandDuration = Duration(milliseconds: 1200);

  Timer? _timer;
  var _showBranding = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_brandDuration, () {
      if (mounted) {
        setState(() => _showBranding = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showBranding) {
      return const FieldPulseSplashScreen();
    }

    return Consumer<AppState>(
      builder: (_, state, _) {
        if (!state.restored) {
          return const Scaffold(
            backgroundColor: Color(0xFF031733),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF11E5DF)),
            ),
          );
        }

        return state.signedIn ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
