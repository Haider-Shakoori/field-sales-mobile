import 'package:flutter/material.dart';

class FieldPulseSplashScreen extends StatelessWidget {
  const FieldPulseSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF031733),
    body: SizedBox.expand(
      child: Image(
        image: AssetImage('assets/branding/fieldpulse_splash.webp'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    ),
  );
}
