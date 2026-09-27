import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class FieldPulseSplashScreen extends StatelessWidget {
  const FieldPulseSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF031733),
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05234D), Color(0xFF031733), Color(0xFF020E22)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _SplashGlow(
            alignment: Alignment(-1.25, -1.15),
            size: 430,
            color: Color(0x3329D8FF),
          ),
          const _SplashGlow(
            alignment: Alignment(1.2, 1.1),
            size: 520,
            color: Color(0x261D5CFF),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 190,
                        height: 190,
                        child: CustomPaint(painter: _FieldPulseMarkPainter()),
                      ),
                      const SizedBox(height: 24),
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF1C65FF), Color(0xFF16E2DF)],
                        ).createShader(bounds),
                        child: const Text(
                          'FieldPulse',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 58,
                            height: 0.95,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 25,
                            height: 1,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: 'by ',
                              style: TextStyle(color: Color(0xFFB8C4D6)),
                            ),
                            TextSpan(
                              text: 'BusinessOS',
                              style: TextStyle(
                                color: Color(0xFF2A72FF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SplashGlow extends StatelessWidget {
  const _SplashGlow({
    required this.alignment,
    required this.size,
    required this.color,
  });

  final Alignment alignment;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _FieldPulseMarkPainter extends CustomPainter {
  const _FieldPulseMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 200;
    canvas.save();
    canvas.scale(scale, scale);

    final outer = Path()
      ..moveTo(100, 10)
      ..cubicTo(47, 10, 15, 47, 15, 91)
      ..cubicTo(15, 139, 60, 169, 100, 194)
      ..cubicTo(140, 169, 185, 139, 185, 91)
      ..cubicTo(185, 47, 153, 10, 100, 10)
      ..close();

    final outerPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(30, 25),
        const Offset(165, 175),
        const [Color(0xFF0B5EFF), Color(0xFF15E4D7), Color(0xFF0B64FF)],
        const [0, 0.48, 1],
      );

    canvas.drawPath(outer, outerPaint);

    final inner = Path()
      ..moveTo(100, 38)
      ..cubicTo(64, 38, 43, 61, 43, 92)
      ..cubicTo(43, 116, 58, 132, 76, 145)
      ..cubicTo(89, 154, 95, 163, 100, 174)
      ..cubicTo(105, 163, 111, 154, 124, 145)
      ..cubicTo(142, 132, 157, 116, 157, 92)
      ..cubicTo(157, 61, 136, 38, 100, 38)
      ..close();

    canvas.drawPath(inner, Paint()..color = const Color(0xFF062346));

    final road = Path()
      ..moveTo(38, 145)
      ..cubicTo(70, 130, 93, 126, 150, 116)
      ..cubicTo(119, 134, 87, 144, 62, 171)
      ..lineTo(48, 160)
      ..close();

    canvas.drawPath(
      road,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(40, 135),
          const Offset(145, 120),
          const [Color(0xFF1F6CFF), Color(0xFF11CFE3)],
        ),
    );

    final barPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(60, 68),
        const Offset(135, 128),
        const [Color(0xFF1BBFFF), Color(0xFF20E2CC)],
      );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(61, 101, 25, 32),
        const Radius.circular(5),
      ),
      barPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(91, 81, 25, 48),
        const Radius.circular(5),
      ),
      barPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(121, 58, 25, 64),
        const Radius.circular(5),
      ),
      barPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
