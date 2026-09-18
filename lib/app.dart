import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';

class FieldSalesApp extends StatelessWidget {
  const FieldSalesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Field Sales', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5), brightness: Brightness.light), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF6F7FB), cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero)),
    home: Consumer<AppState>(builder: (_, state, __) {
      if (!state.restored) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return state.signedIn ? const DashboardScreen() : const LoginScreen();
    }),
  );
}
