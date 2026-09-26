import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/dashboard_screen.dart';
import 'ui/fieldpulse_splash_screen.dart';
import 'ui/login_screen.dart';
import 'ui/management_dashboard_screen.dart';

class FieldSalesApp extends StatelessWidget {
  const FieldSalesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FieldPulse',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0B74E5),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    ),
    home: const _StartupGate(),
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

        if (!state.signedIn) {
          return const LoginScreen();
        }

        return state.session?.isManagement == true
            ? const ManagementDashboardScreen()
            : const DashboardScreen();
      },
    );
  }
}
